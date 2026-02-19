import SwiftUI
import Foundation

struct LocalDomainCheck: Identifiable {
    let id: String
    let title: String
    let isPassing: Bool
    let detail: String
}

private enum LocalDomainSetupError: LocalizedError {
    case invalidSuffix
    case missingHomebrew

    var errorDescription: String? {
        switch self {
        case .invalidSuffix:
            return "Domain suffix is invalid."
        case .missingHomebrew:
            return "Homebrew is required for automatic dnsmasq setup."
        }
    }
}

/// Handles automatic local-domain setup and health checks.
actor LocalDomainService {
    static let shared = LocalDomainService()

    private let shell = ShellExecutor.shared
    private let dnsmasqPort = 53535
    private let managedDnsmasqConfig = "colimaui.conf"
    private var lastRouteSyncAt: Date = .distantPast
    private var lastRoutesDigest: Int = 0

    private init() {}

    func normalizeSuffix(_ suffix: String) -> String {
        suffix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    func setupAndCheck(suffix: String) async throws -> [LocalDomainCheck] {
        let normalized = normalizeSuffix(suffix)
        guard !normalized.isEmpty else {
            throw LocalDomainSetupError.invalidSuffix
        }

        var issues: [String] = []

        do {
            try await ensurePrivilegedSetupFiles(for: normalized)
        } catch {
            issues.append("Privileged setup: \(error.localizedDescription)")
        }

        do {
            try await setupDNS(for: normalized)
        } catch {
            issues.append("DNS: \(error.localizedDescription)")
        }

        do {
            try await setupResolver(for: normalized)
        } catch {
            issues.append("Resolver: \(error.localizedDescription)")
        }

        do {
            try await setupTLS(for: normalized)
        } catch {
            issues.append("TLS: \(error.localizedDescription)")
        }

        do {
            _ = try await ensureColimaRunning()
        } catch {
            issues.append("Colima: \(error.localizedDescription)")
        }

        do {
            _ = try await ensureReverseProxy(for: normalized)
        } catch {
            issues.append("Reverse proxy: \(error.localizedDescription)")
        }

        await syncProxyRoutes(suffix: normalized, force: true)
        _ = try? await shell.run("dscacheutil -flushcache >/dev/null 2>&1 || true")

        if !issues.isEmpty {
            print("Local domain setup completed with issues: \(issues.joined(separator: " | "))")
        }

        return await checkSetup(suffix: normalized)
    }

    func unsetup(suffix: String) async throws -> [LocalDomainCheck] {
        let normalized = normalizeSuffix(suffix)
        guard !normalized.isEmpty else {
            throw LocalDomainSetupError.invalidSuffix
        }

        _ = try? await shell.run("docker rm -f colimaui-proxy >/dev/null 2>&1")

        let proxyBase = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ColimaUI/proxy", isDirectory: true)
        let proxyBaseEscaped = Self.shellEscape(proxyBase.path)
        _ = try? await shell.run("rm -rf \(proxyBaseEscaped)")

        if await commandSucceeds("command -v brew >/dev/null 2>&1") {
            if await commandSucceeds("command -v mkcert >/dev/null 2>&1") {
                _ = try? await shell.run("mkcert -uninstall >/dev/null 2>&1 || true")
            }

            _ = try? await shell.run("brew services stop dnsmasq >/dev/null 2>&1 || true")
            _ = try? await shell.run("brew services cleanup >/dev/null 2>&1 || true")
            _ = try? await shell.run("launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/homebrew.mxcl.dnsmasq.plist >/dev/null 2>&1 || true")
            _ = try? await shell.run("rm -f ~/Library/LaunchAgents/homebrew.mxcl.dnsmasq.plist >/dev/null 2>&1 || true")

            let brewPrefix = ((try? await shell.run("brew --prefix")) ?? "/opt/homebrew")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let managedConf = "\(brewPrefix)/etc/dnsmasq.d/\(managedDnsmasqConfig)"
            let managedConfEscaped = Self.shellEscape(managedConf)
            _ = try? await shell.run("rm -f \(managedConfEscaped)")

            let dnsmasqConf = "\(brewPrefix)/etc/dnsmasq.conf"
            let dnsmasqConfEscaped = Self.shellEscape(dnsmasqConf)
            _ = try? await shell.run("""
            if [ -f \(dnsmasqConfEscaped) ]; then
              sed -i '' '/^address=\\/.\(normalized)\\/127\\.0\\.0\\.1$/d' \(dnsmasqConfEscaped) || true
              sed -i '' '/^address=\\/.colima\\/127\\.0\\.0\\.1$/d' \(dnsmasqConfEscaped) || true
            fi
            """)

            _ = try? await shell.run("brew uninstall --formula dnsmasq >/dev/null 2>&1 || true")
            _ = try? await shell.run("brew uninstall --formula mkcert >/dev/null 2>&1 || true")
        }

        var resolverTargets = ["/etc/resolver/\(normalized)"]
        if normalized != "colima" {
            resolverTargets.append("/etc/resolver/colima")
        }
        let resolverCleanup = "rm -f " + resolverTargets.map(Self.shellEscape).joined(separator: " ")
        _ = try? await shell.runPrivileged(
            resolverCleanup,
            prompt: "ColimaUI needs permission to remove the local website address settings it previously added."
        )
        _ = try? await shell.run("dscacheutil -flushcache >/dev/null 2>&1 || true")

        return await checkSetup(suffix: normalized)
    }

    func checkSetup(suffix: String) async -> [LocalDomainCheck] {
        let normalized = normalizeSuffix(suffix)
        guard !normalized.isEmpty else {
            return [
                LocalDomainCheck(
                    id: "suffix",
                    title: "Domain suffix",
                    isPassing: false,
                    detail: "Suffix is empty."
                )
            ]
        }

        let suffixEscaped = Self.shellEscape(normalized)
        let dnsPort = dnsmasqPort
        let certDirEscaped = Self.shellEscape(certificateDirectory().path)
        let probe = """
        suffix=\(suffixEscaped)
        dns_port=\(dnsPort)
        cert_dir=\(certDirEscaped)

        has_brew=0
        command -v brew >/dev/null 2>&1 && has_brew=1

        colima_running=0
        colima status >/dev/null 2>&1 && colima_running=1

        docker_reachable=0
        if [ "$colima_running" -eq 1 ]; then
          docker info >/dev/null 2>&1 && docker_reachable=1
        fi

        dnsmasq_installed=0
        command -v dnsmasq >/dev/null 2>&1 && dnsmasq_installed=1

        dnsmasq_status="unknown"
        dnsmasq_running=0
        dnsmasq_errored=0

        if lsof -nP -iTCP:$dns_port -iUDP:$dns_port 2>/dev/null | grep -qi 'dnsmasq'; then
          dnsmasq_status="started"
          dnsmasq_running=1
        fi

        launch_exit="$(launchctl print gui/$(id -u)/homebrew.mxcl.dnsmasq 2>/dev/null | awk -F'= ' '/last exit code =/{print $2; exit}')"
        if [ -n "$launch_exit" ] && [ "$launch_exit" != "0" ] && [ "$dnsmasq_running" -eq 0 ]; then
          dnsmasq_status="error"
          dnsmasq_errored=1
        fi

        wildcard_configured=0
        line="address=/.$suffix/127.0.0.1"
        for prefix in /opt/homebrew /usr/local; do
          managed="$prefix/etc/dnsmasq.d/colimaui.conf"
          if [ -f "$managed" ] && grep -Fqx "$line" "$managed"; then
            wildcard_configured=1
            break
          fi
          conf="$prefix/etc/dnsmasq.conf"
          if [ -f "$conf" ] && grep -Fqx "$line" "$conf"; then
            wildcard_configured=1
            break
          fi
        done

        resolver_configured=0
        resolver="/etc/resolver/$suffix"
        if [ -f "$resolver" ] && \
           grep -Fqx 'nameserver 127.0.0.1' "$resolver" && \
           grep -Fqx "port $dns_port" "$resolver"; then
          resolver_configured=1
        fi

        wildcard_resolution=0
        if [ "$dnsmasq_running" -eq 1 ] && [ "$resolver_configured" -eq 1 ]; then
          dscacheutil -q host -a name "colimaui-check.$suffix" 2>/dev/null | grep -q 'ip_address: 127.0.0.1' && wildcard_resolution=1
        fi

        reverse_proxy_running=0
        if [ "$docker_reachable" -eq 1 ]; then
          docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq 'colimaui-proxy' && reverse_proxy_running=1
        fi

        mkcert_installed=0
        command -v mkcert >/dev/null 2>&1 && mkcert_installed=1

        cert_configured=0
        [ -f "$cert_dir/$suffix.pem" ] && [ -f "$cert_dir/$suffix-key.pem" ] && cert_configured=1

        domain_index_reachable=0
        if [ "$reverse_proxy_running" -eq 1 ]; then
          curl -skf --connect-timeout 1 --max-time 1 "https://index.$suffix" >/dev/null 2>&1 && domain_index_reachable=1
        fi

        printf 'has_brew=%s\\n' "$has_brew"
        printf 'colima_running=%s\\n' "$colima_running"
        printf 'docker_reachable=%s\\n' "$docker_reachable"
        printf 'dnsmasq_installed=%s\\n' "$dnsmasq_installed"
        printf 'dnsmasq_running=%s\\n' "$dnsmasq_running"
        printf 'dnsmasq_errored=%s\\n' "$dnsmasq_errored"
        printf 'wildcard_configured=%s\\n' "$wildcard_configured"
        printf 'resolver_configured=%s\\n' "$resolver_configured"
        printf 'wildcard_resolution=%s\\n' "$wildcard_resolution"
        printf 'reverse_proxy_running=%s\\n' "$reverse_proxy_running"
        printf 'mkcert_installed=%s\\n' "$mkcert_installed"
        printf 'cert_configured=%s\\n' "$cert_configured"
        printf 'domain_index_reachable=%s\\n' "$domain_index_reachable"
        """

        let output = (try? await shell.run(probe)) ?? ""
        let flags = parseProbeFlags(output)

        let hasBrew = flags["has_brew"] == true
        let colimaRunning = flags["colima_running"] == true
        let dockerReachable = flags["docker_reachable"] == true
        let dnsmasqInstalled = flags["dnsmasq_installed"] == true
        let dnsmasqRunning = flags["dnsmasq_running"] == true
        let dnsmasqErrored = flags["dnsmasq_errored"] == true
        let wildcardConfigured = flags["wildcard_configured"] == true
        let resolverConfigured = flags["resolver_configured"] == true
        let wildcardResolution = flags["wildcard_resolution"] == true
        let reverseProxyRunning = flags["reverse_proxy_running"] == true
        let mkcertInstalled = flags["mkcert_installed"] == true
        let certConfigured = flags["cert_configured"] == true
        let domainIndexReachable = flags["domain_index_reachable"] == true

        return [
            LocalDomainCheck(
                id: "brew",
                title: "Homebrew",
                isPassing: hasBrew,
                detail: hasBrew ? "Installed" : "Missing"
            ),
            LocalDomainCheck(
                id: "colima",
                title: "Colima runtime",
                isPassing: colimaRunning,
                detail: colimaRunning ? "Running" : "Not running"
            ),
            LocalDomainCheck(
                id: "docker",
                title: "Docker API",
                isPassing: dockerReachable,
                detail: dockerReachable ? "Reachable" : "Unavailable (start Colima)"
            ),
            LocalDomainCheck(
                id: "dnsmasq-binary",
                title: "dnsmasq",
                isPassing: dnsmasqInstalled,
                detail: dnsmasqInstalled ? "Installed" : "Missing"
            ),
            LocalDomainCheck(
                id: "dnsmasq-service",
                title: "dnsmasq service",
                isPassing: dnsmasqRunning,
                detail: dnsmasqRunning ? "Running on \(dnsPort)" : (dnsmasqErrored ? "Error state" : "Not running")
            ),
            LocalDomainCheck(
                id: "dnsmasq-wildcard",
                title: "Wildcard DNS",
                isPassing: wildcardConfigured,
                detail: wildcardConfigured ? "*.\(normalized) -> 127.0.0.1 configured" : "Wildcard rule missing"
            ),
            LocalDomainCheck(
                id: "resolver",
                title: "macOS resolver",
                isPassing: resolverConfigured,
                detail: resolverConfigured ? "/etc/resolver/\(normalized) configured" : "Resolver file missing or port mismatch"
            ),
            LocalDomainCheck(
                id: "resolution",
                title: "Wildcard resolution",
                isPassing: wildcardResolution,
                detail: wildcardResolution ? "Hostnames resolve to 127.0.0.1" : "Wildcard lookup not resolving"
            ),
            LocalDomainCheck(
                id: "proxy",
                title: "Reverse proxy",
                isPassing: reverseProxyRunning,
                detail: reverseProxyRunning ? "colimaui-proxy running" : (dockerReachable ? "colimaui-proxy is not running" : "Docker unavailable")
            ),
            LocalDomainCheck(
                id: "mkcert",
                title: "mkcert",
                isPassing: mkcertInstalled,
                detail: mkcertInstalled ? "Installed" : "Missing"
            ),
            LocalDomainCheck(
                id: "cert",
                title: "TLS certificate",
                isPassing: certConfigured,
                detail: certConfigured ? "Wildcard certificate generated" : "Certificate missing"
            ),
            LocalDomainCheck(
                id: "index",
                title: "Domain index",
                isPassing: domainIndexReachable,
                detail: domainIndexReachable ? "https://index.\(normalized) is reachable" : "Index domain is not reachable"
            )
        ]
    }

    private func setupDNS(for suffix: String) async throws {
        guard await commandSucceeds("command -v brew >/dev/null 2>&1") else {
            throw LocalDomainSetupError.missingHomebrew
        }

        if !(await commandSucceeds("brew list dnsmasq >/dev/null 2>&1")) {
            _ = try await shell.run("brew install dnsmasq")
        }

        let brewPrefix = try await shell.run("brew --prefix")
        let prefix = brewPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let managedDir = "\(prefix)/etc/dnsmasq.d"
        let managedConf = "\(managedDir)/\(managedDnsmasqConfig)"
        let managedDirEscaped = Self.shellEscape(managedDir)
        let managedConfEscaped = Self.shellEscape(managedConf)
        let configBody = [
            "# Managed by ColimaUI",
            "listen-address=127.0.0.1",
            "bind-interfaces",
            "port=\(dnsmasqPort)",
            "address=/.\(suffix)/127.0.0.1"
        ].joined(separator: "\n") + "\n"
        let configBodyEscaped = Self.shellEscape(configBody)

        let hasManagedConfig = await commandSucceeds(
            "test -f \(managedConfEscaped) && grep -Fqx 'listen-address=127.0.0.1' \(managedConfEscaped) && grep -Fqx 'bind-interfaces' \(managedConfEscaped) && grep -Fqx 'port \(dnsmasqPort)' \(managedConfEscaped) && grep -Fqx 'address=/.\(suffix)/127.0.0.1' \(managedConfEscaped)"
        )

        if !hasManagedConfig {
            do {
                _ = try await shell.run("mkdir -p \(managedDirEscaped)")
                _ = try await shell.run("printf '%s' \(configBodyEscaped) > \(managedConfEscaped)")
            } catch {
                _ = try await shell.runPrivileged(
                    "mkdir -p \(managedDirEscaped) && printf '%s' \(configBodyEscaped) > \(managedConfEscaped)",
                    prompt: "ColimaUI needs permission to set up local website addresses for your containers."
                )
            }
        }

        _ = try? await shell.run("brew services stop dnsmasq >/dev/null 2>&1 || true")
        _ = try? await shell.run("launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/homebrew.mxcl.dnsmasq.plist >/dev/null 2>&1 || true")
        _ = try? await shell.run("rm -f ~/Library/LaunchAgents/homebrew.mxcl.dnsmasq.plist >/dev/null 2>&1 || true")
        _ = try? await shell.run("brew services cleanup >/dev/null 2>&1 || true")
        _ = try? await shell.run("brew services start dnsmasq >/dev/null 2>&1")

        if !(await waitForDnsmasqStart()) {
            _ = try? await shell.run("brew services restart dnsmasq >/dev/null 2>&1")
        }

        if !(await waitForDnsmasqStart()) {
            let status = await dnsmasqServiceStatus()
            throw ShellError.commandFailed("dnsmasq service failed to start (\(status))")
        }
    }

    private func dnsmasqServiceStatus() async -> String {
        let status = (try? await shell.run("brew services list 2>/dev/null | awk '$1==\"dnsmasq\"{print $2; exit}'")) ?? ""
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? "unknown" : normalized
    }

    private func isDnsmasqRunning() async -> Bool {
        if await commandSucceeds("lsof -nP -iTCP:\(dnsmasqPort) -iUDP:\(dnsmasqPort) 2>/dev/null | grep -qi 'dnsmasq'") {
            return true
        }
        return (await dnsmasqServiceStatus()) == "started"
    }

    private func waitForDnsmasqStart(attempts: Int = 12, delayMs: UInt64 = 250) async -> Bool {
        for _ in 0..<attempts {
            if await isDnsmasqRunning() {
                return true
            }
            try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
        }
        return false
    }

    private func setupResolver(for suffix: String) async throws {
        let resolverPath = "/etc/resolver/\(suffix)"
        let resolverEscaped = Self.shellEscape(resolverPath)
        let hasResolver = await commandSucceeds(
            "test -f \(resolverEscaped) && grep -Fqx 'nameserver 127.0.0.1' \(resolverEscaped) && grep -Fqx 'port \(dnsmasqPort)' \(resolverEscaped)"
        )
        if !hasResolver {
            throw ShellError.commandFailed("Resolver is missing or invalid at \(resolverPath)")
        }
    }

    private func setupTLS(for suffix: String) async throws {
        guard await commandSucceeds("command -v brew >/dev/null 2>&1") else {
            throw LocalDomainSetupError.missingHomebrew
        }

        if !(await commandSucceeds("brew list mkcert >/dev/null 2>&1")) {
            _ = try await shell.run("brew install mkcert")
        }

        _ = try? await shell.run("mkcert -install")

        let certDir = certificateDirectory()
        try FileManager.default.createDirectory(at: certDir, withIntermediateDirectories: true)

        let certURL = certDir.appendingPathComponent("\(suffix).pem")
        let keyURL = certDir.appendingPathComponent("\(suffix)-key.pem")

        if !FileManager.default.fileExists(atPath: certURL.path) || !FileManager.default.fileExists(atPath: keyURL.path) {
            let certEscaped = Self.shellEscape(certURL.path)
            let keyEscaped = Self.shellEscape(keyURL.path)
            _ = try await shell.run(
                "mkcert -cert-file \(certEscaped) -key-file \(keyEscaped) '*.\(suffix)' \(suffix) index.\(suffix) localhost 127.0.0.1 ::1"
            )
        }

        try writeTLSDynamicConfig(for: suffix)
    }

    private func ensureReverseProxy(for suffix: String) async throws -> String {
        let running = try? await shell.run("docker ps --format '{{.Names}} {{.Image}}'")
        let runningLines = (running ?? "")
            .split(separator: "\n")
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }

        let hasManagedProxy = runningLines.contains { $0.hasPrefix("colimaui-proxy ") }
        if hasManagedProxy {
            return "Managed reverse proxy already running."
        }

        _ = try? await shell.run("docker rm -f colimaui-proxy >/dev/null 2>&1")

        let dynamicDir = proxyDynamicDirectory()
        let certDir = certificateDirectory()
        try FileManager.default.createDirectory(at: dynamicDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: certDir, withIntermediateDirectories: true)

        let dynamicDirEscaped = Self.shellEscape(dynamicDir.path)
        let certDirEscaped = Self.shellEscape(certDir.path)

        let command = """
        docker run -d --name colimaui-proxy --restart unless-stopped \
          -p 80:80 -p 443:443 \
          -v \(dynamicDirEscaped):/etc/traefik/dynamic \
          -v \(certDirEscaped):/etc/traefik/certs:ro \
          traefik:v2.11 \
          --providers.file.directory=/etc/traefik/dynamic \
          --providers.file.watch=true \
          --api.dashboard=true \
          --entrypoints.web.address=:80 \
          --entrypoints.web.http.redirections.entryPoint.to=websecure \
          --entrypoints.web.http.redirections.entryPoint.scheme=https \
          --entrypoints.websecure.http.tls=true \
          --entrypoints.websecure.address=:443
        """

        _ = try await shell.run(command)
        return "Started colimaui-proxy with default routing."
    }

    private func ensureColimaRunning() async throws -> String {
        if await commandSucceeds("colima status >/dev/null 2>&1") {
            return "Colima already running."
        }

        _ = try await shell.run("colima start")
        return "Colima started."
    }

    func syncProxyRoutes(suffix: String, force: Bool = false) async {
        let normalized = normalizeSuffix(suffix)
        guard !normalized.isEmpty else { return }
        guard await commandSucceeds("docker info >/dev/null 2>&1") else { return }

        let now = Date()
        if !force, now.timeIntervalSince(lastRouteSyncAt) < 2 {
            return
        }
        lastRouteSyncAt = now

        do {
            let yaml = try await buildRoutesYAML(for: normalized)
            let digest = yaml.hashValue
            if force || digest != lastRoutesDigest {
                let routesURL = proxyDynamicDirectory().appendingPathComponent("routes.yml")
                try yaml.write(to: routesURL, atomically: true, encoding: .utf8)
                lastRoutesDigest = digest
            }

            try writeTLSDynamicConfig(for: normalized)
        } catch {
            // Ignore sync failures during background refresh loops.
        }
    }

    private func buildRoutesYAML(for suffix: String) async throws -> String {
        let output = try await shell.run("docker ps --format \"{{json .}}\"")
        let lines = output.split(separator: "\n")
        let decoder = JSONDecoder()
        let containers = lines.compactMap { line -> Container? in
            guard let data = String(line).data(using: .utf8) else { return nil }
            return try? decoder.decode(Container.self, from: data)
        }

        let ipMap = try await runningContainerIPs()

        struct Route {
            let name: String
            let rule: String
            let service: String
            let middlewares: [String]
        }

        var routes: [Route] = []
        var serviceNames = Set<String>()
        var serviceURLs: [String: String] = [:]
        var routeRules = Set<String>()
        var routeIndex = 0

        func addRoute(rule: String, service: String, middlewares: [String] = []) {
            guard routeRules.insert("\(rule)|\(service)").inserted else { return }
            routeIndex += 1
            routes.append(Route(name: "r\(routeIndex)", rule: rule, service: service, middlewares: middlewares))
        }

        addRoute(
            rule: "Host(`index.\(suffix)`) && Path(`/`)",
            service: "api@internal",
            middlewares: ["index-redirect"]
        )
        addRoute(
            rule: "Host(`index.\(suffix)`) && (PathPrefix(`/dashboard`) || PathPrefix(`/api`))",
            service: "api@internal"
        )

        for container in containers {
            let labels = parseLabels(container.Labels)
            guard let port = preferredHTTPPort(for: container, labels: labels) else { continue }
            guard let ip = ipForContainer(shortID: container.containerID, ipMap: ipMap) else { continue }

            let shortID = sanitizeID(container.containerID)
            let serviceName = "s\(shortID)p\(port)"

            if serviceNames.insert(serviceName).inserted {
                serviceURLs[serviceName] = "http://\(ip):\(port)"
            }

            let domains = container.localDomains(domainSuffix: suffix)
            for domain in domains {
                if Container.isWildcardDomain(domain) {
                    let root = String(domain.dropFirst(2))
                    addRoute(rule: "HostRegexp(`{subdomain:.+}.\(root)`)", service: serviceName)
                    continue
                }

                addRoute(rule: "Host(`\(domain)`)", service: serviceName)
                addRoute(rule: "HostRegexp(`{subdomain:.+}.\(domain)`)", service: serviceName)
            }
        }

        var yaml: [String] = []
        yaml.append("http:")
        yaml.append("  routers:")
        if routes.isEmpty {
            yaml.append("    r1:")
            yaml.append("      rule: \"Host(`index.\(suffix)`)\"")
            yaml.append("      entryPoints: [\"web\", \"websecure\"]")
            yaml.append("      service: api@internal")
            yaml.append("      tls: {}")
        } else {
            for route in routes {
                yaml.append("    \(route.name):")
                yaml.append("      rule: \"\(route.rule)\"")
                yaml.append("      entryPoints: [\"web\", \"websecure\"]")
                yaml.append("      service: \(route.service)")
                if !route.middlewares.isEmpty {
                    let middlewares = route.middlewares.map { "\"\($0)\"" }.joined(separator: ", ")
                    yaml.append("      middlewares: [\(middlewares)]")
                }
                yaml.append("      tls: {}")
            }
        }

        yaml.append("  middlewares:")
        yaml.append("    index-redirect:")
        yaml.append("      redirectRegex:")
        yaml.append("        regex: \"^https?://([^/]+)/?$\"")
        yaml.append("        replacement: \"https://$1/dashboard/\"")
        yaml.append("        permanent: false")

        yaml.append("  services:")
        if serviceURLs.isEmpty {
            yaml.append("    noop:")
            yaml.append("      loadBalancer:")
            yaml.append("        servers:")
            yaml.append("          - url: \"http://127.0.0.1:65535\"")
        } else {
            for serviceName in serviceURLs.keys.sorted() {
                guard let url = serviceURLs[serviceName] else { continue }
                yaml.append("    \(serviceName):")
                yaml.append("      loadBalancer:")
                yaml.append("        servers:")
                yaml.append("          - url: \"\(url)\"")
            }
        }

        return yaml.joined(separator: "\n") + "\n"
    }

    private func runningContainerIPs() async throws -> [String: String] {
        let command = """
        ids="$(docker ps -q)"
        if [ -z "$ids" ]; then
          exit 0
        fi
        for id in ${=ids}; do
          docker inspect --format '{{.Id}}|{{range .NetworkSettings.Networks}}{{if .IPAddress}}{{.IPAddress}} {{end}}{{end}}' "$id"
        done
        """
        let output = try await shell.run(command)

        var result: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let id = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let ip = parts[1]
                .split(separator: " ")
                .map(String.init)
                .first(where: { !$0.isEmpty }) ?? ""
            if !id.isEmpty, !ip.isEmpty {
                result[id] = ip
            }
        }
        return result
    }

    private func preferredHTTPPort(for container: Container, labels: [String: String]) -> Int? {
        if let raw = labels["dev.colimaui.http-port"],
           let overridePort = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           (1...65535).contains(overridePort) {
            return overridePort
        }

        let candidates = inferredContainerPorts(from: container.Ports)
        guard !candidates.isEmpty else { return nil }

        let preferred = [80, 8080, 3000, 5173, 8000, 5000, 4200, 4000, 9000, 8888, 443]
        if let match = preferred.first(where: { candidates.contains($0) }) {
            return match
        }
        return candidates.first
    }

    private func inferredContainerPorts(from ports: String) -> [Int] {
        let mappings = ports
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var seen = Set<Int>()
        var result: [Int] = []

        for mapping in mappings {
            var candidate: Int?
            if let arrowRange = mapping.range(of: "->") {
                let rhs = String(mapping[arrowRange.upperBound...])
                if let slash = rhs.firstIndex(of: "/") {
                    candidate = Int(rhs[..<slash])
                } else {
                    candidate = Int(rhs)
                }
            } else if !mapping.contains(":"),
                      let slash = mapping.firstIndex(of: "/") {
                candidate = Int(mapping[..<slash])
            }

            if let port = candidate, (1...65535).contains(port), seen.insert(port).inserted {
                result.append(port)
            }
        }

        return result
    }

    private func parseLabels(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            result[parts[0]] = parts[1]
        }
        return result
    }

    private func ipForContainer(shortID: String, ipMap: [String: String]) -> String? {
        let lower = shortID.lowercased()
        if let exact = ipMap[lower] {
            return exact
        }
        return ipMap.first(where: { $0.key.hasPrefix(lower) })?.value
    }

    private func sanitizeID(_ id: String) -> String {
        let cleaned = id.lowercased().filter { $0.isLetter || $0.isNumber }
        if cleaned.count >= 12 {
            return String(cleaned.prefix(12))
        }
        return cleaned.isEmpty ? "container" : cleaned
    }

    private func proxyDynamicDirectory() -> URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ColimaUI/proxy/dynamic", isDirectory: true)
        return base
    }

    private func certificateDirectory() -> URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ColimaUI/proxy/certs", isDirectory: true)
        return base
    }

    private func writeTLSDynamicConfig(for suffix: String) throws {
        let dynamicDir = proxyDynamicDirectory()
        try FileManager.default.createDirectory(at: dynamicDir, withIntermediateDirectories: true)

        let content = """
        tls:
          stores:
            default:
              defaultCertificate:
                certFile: /etc/traefik/certs/\(suffix).pem
                keyFile: /etc/traefik/certs/\(suffix)-key.pem
        """

        let url = dynamicDir.appendingPathComponent("tls.yml")
        try content.appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func ensurePrivilegedSetupFiles(for suffix: String) async throws {
        let resolverPath = "/etc/resolver/\(suffix)"
        let resolverEscaped = Self.shellEscape(resolverPath)
        let resolverReady = await commandSucceeds(
            "test -f \(resolverEscaped) && grep -Fqx 'nameserver 127.0.0.1' \(resolverEscaped) && grep -Fqx 'port \(dnsmasqPort)' \(resolverEscaped)"
        )

        let brewPrefix = ((try? await shell.run("brew --prefix")) ?? "/opt/homebrew")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let managedConf = "\(brewPrefix)/etc/dnsmasq.d/\(managedDnsmasqConfig)"
        let managedEscaped = Self.shellEscape(managedConf)
        let managedReady = await commandSucceeds(
            "test -f \(managedEscaped) && grep -Fqx 'listen-address=127.0.0.1' \(managedEscaped) && grep -Fqx 'bind-interfaces' \(managedEscaped) && grep -Fqx 'port \(dnsmasqPort)' \(managedEscaped) && grep -Fqx 'address=/.\(suffix)/127.0.0.1' \(managedEscaped)"
        )

        if resolverReady && managedReady {
            return
        }

        let managedDir = "\(brewPrefix)/etc/dnsmasq.d"
        let managedDirEscaped = Self.shellEscape(managedDir)
        let configBody = [
            "# Managed by ColimaUI",
            "listen-address=127.0.0.1",
            "bind-interfaces",
            "port=\(dnsmasqPort)",
            "address=/.\(suffix)/127.0.0.1"
        ].joined(separator: "\n") + "\n"
        let configBodyEscaped = Self.shellEscape(configBody)
        let resolverBodyEscaped = Self.shellEscape("nameserver 127.0.0.1\nport \(dnsmasqPort)\n")

        let command = """
        mkdir -p \(managedDirEscaped) && \
        printf '%s' \(configBodyEscaped) > \(managedEscaped) && \
        mkdir -p /etc/resolver && \
        printf '%s' \(resolverBodyEscaped) > \(resolverEscaped)
        """

        _ = try await shell.runPrivileged(
            command,
            prompt: "ColimaUI needs permission to turn on local website addresses, so container apps open by name instead of port numbers."
        )
    }

    private func commandSucceeds(_ command: String) async -> Bool {
        do {
            _ = try await shell.run(command)
            return true
        } catch {
            return false
        }
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func parseProbeFlags(_ output: String) -> [String: Bool] {
        var result: [String: Bool] = [:]

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            result[parts[0]] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        }

        return result
    }
}

/// App settings view
struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 2.0
    @AppStorage("showStoppedContainers") private var showStoppedContainers: Bool = true
    @AppStorage("enableContainerDomains") private var enableContainerDomains: Bool = true
    @AppStorage("containerDomainSuffix") private var containerDomainSuffix: String = "colima"
    @AppStorage("preferHTTPSDomains") private var preferHTTPSDomains: Bool = false
    @State private var isColimaHovered = false
    @State private var domainSuffixDraft: String = ""
    @State private var setupChecks: [LocalDomainCheck] = []
    @State private var isAutoSetupRunning = false
    @State private var setupStatusLabel: String = "Pending"
    @State private var suffixApplyTask: Task<Void, Never>?
    @State private var setupTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Header
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(Theme.textPrimary)

                // Settings sections
                VStack(alignment: .leading, spacing: 24) {
                    // Refresh interval
                    SettingsRow(
                        icon: "arrow.clockwise",
                        title: "Refresh Interval",
                        subtitle: "How often to update container stats"
                    ) {
                        Picker("", selection: $refreshInterval) {
                            Text("1s").tag(1.0)
                            Text("2s").tag(2.0)
                            Text("5s").tag(5.0)
                            Text("10s").tag(10.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }

                    Divider()
                        .background(Theme.cardBorder)

                    // Show stopped containers
                    SettingsRow(
                        icon: "eye",
                        title: "Show Stopped Containers",
                        subtitle: "Display exited containers in lists"
                    ) {
                        Toggle("", isOn: $showStoppedContainers)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    Divider()
                        .background(Theme.cardBorder)

                    SettingsRow(
                        icon: "network",
                        title: "Local Domains",
                        subtitle: "Show domain links for containers"
                    ) {
                        Toggle("", isOn: $enableContainerDomains)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }

                    SettingsRow(
                        icon: "globe",
                        title: "Domain Suffix",
                        subtitle: "Used for generated domains (service.project.suffix)"
                    ) {
                        TextField(".colima", text: $domainSuffixDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 220)
                            .disabled(!enableContainerDomains)
                            .onSubmit {
                                applyDomainSuffix(domainSuffixDraft, triggerCheck: true)
                            }
                    }

                    SettingsRow(
                        icon: "lock",
                        title: "Prefer HTTPS",
                        subtitle: "Open domain links with https:// instead of http://"
                    ) {
                        Toggle("", isOn: $preferHTTPSDomains)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!enableContainerDomains)
                    }

                    SettingsRow(
                        icon: "gear.badge.checkmark",
                        title: "Automatic Setup",
                        subtitle: "Run setup, verify health, or remove local-domain setup"
                    ) {
                        automaticSetupControls
                    }

                    SettingsRow(
                        icon: "list.bullet.rectangle",
                        title: "Domain Index",
                        subtitle: "Open the live local-domain index page"
                    ) {
                        domainIndexControls
                    }

                    if enableContainerDomains {
                        setupPermissionNote

                        Divider()
                            .background(Theme.cardBorder)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(setupChecks) { check in
                                LocalDomainCheckRow(check: check)
                            }
                        }

                        Divider()
                            .background(Theme.cardBorder)

                        devWorkflowCopyPack
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )

                // About section
                VStack(alignment: .leading, spacing: 16) {
                    // App info
                    HStack(spacing: 12) {
                        Image(systemName: "cube.transparent.fill")
                            .font(.system(size: 32))
                            .foregroundColor(Theme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("ColimaUI")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)

                            Text("Version 1.0.0")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textMuted)
                        }
                    }

                    Text("A native macOS GUI for managing Colima virtual machines and Docker containers.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                        .lineSpacing(2)

                    // Colima attribution
                    VStack(alignment: .leading, spacing: 8) {
                        Text("POWERED BY")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.textMuted)
                            .tracking(0.5)

                        Link(destination: URL(string: "https://github.com/abiosoft/colima")!) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 10) {
                                    Image(systemName: "shippingbox.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(Theme.textSecondary)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text("Colima")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(Theme.textPrimary)

                                        Text("Container runtimes on macOS")
                                            .font(.system(size: 11))
                                            .foregroundColor(Theme.textMuted)
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textMuted)
                                }
                                .padding(12)

                                Text("© 2021 Abiola Ibrahim · MIT License")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.textMuted)
                                    .padding(.leading, 38)
                                    .padding(.bottom, 10)
                            }
                            .background(Color.white.opacity(isColimaHovered ? 0.08 : 0.04))
                            .cornerRadius(8)
                            .animation(.easeOut(duration: 0.15), value: isColimaHovered)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            isColimaHovered = hovering
                        }
                    }

                    // ColimaUI copyright
                    Text("© 2025 Ryan Mish")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textMuted)
                }
                .padding(16)
                .background(Color.white.opacity(0.03))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Theme.cardBorder, lineWidth: 1)
                )

                Spacer()
            }
            .padding(24)
        }
        .background(Theme.contentBackground)
        .onAppear {
            let normalizedStored = normalizedDomainSuffix(containerDomainSuffix)
            if normalizedStored.isEmpty || normalizedStored == "runpoint.local" {
                containerDomainSuffix = "colima"
            } else if normalizedStored != containerDomainSuffix {
                containerDomainSuffix = normalizedStored
            }

            if domainSuffixDraft.isEmpty {
                domainSuffixDraft = ".\(containerDomainSuffix)"
            }
            applyDomainSuffix(domainSuffixDraft, triggerCheck: enableContainerDomains)
        }
        .onChange(of: enableContainerDomains) { _, enabled in
            if enabled {
                applyDomainSuffix(domainSuffixDraft, triggerCheck: true)
            } else {
                setupChecks = []
                setupTask?.cancel()
                setupStatusLabel = "Pending"
            }
        }
        .onChange(of: domainSuffixDraft) { _, newValue in
            suffixApplyTask?.cancel()
            suffixApplyTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    applyDomainSuffix(newValue, triggerCheck: enableContainerDomains)
                }
            }
        }
    }

    private func normalizedDomainSuffix(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func applyDomainSuffix(_ rawValue: String, triggerCheck: Bool) {
        let normalized = normalizedDomainSuffix(rawValue)
        guard !normalized.isEmpty else { return }

        let changed = normalized != containerDomainSuffix
        containerDomainSuffix = normalized

        guard enableContainerDomains, triggerCheck else { return }
        if changed {
            ToastManager.shared.show("Using .\(normalized) for local domains", type: .success)
        }
        runSetupCheckOnly(for: normalized)
    }

    private func runAutomaticSetupAndCheck(for suffix: String) {
        guard !suffix.isEmpty else { return }
        setupTask?.cancel()
        isAutoSetupRunning = true
        setupStatusLabel = "Setting up..."

        setupTask = Task {
            do {
                let checks = try await LocalDomainService.shared.setupAndCheck(suffix: suffix)
                await MainActor.run {
                    if !Task.isCancelled {
                        setupChecks = checks
                        setupStatusLabel = checks.allSatisfy(\.isPassing) ? "Healthy" : "Needs attention"
                    }
                    isAutoSetupRunning = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    isAutoSetupRunning = false
                    setupStatusLabel = "Cancelled"
                }
            } catch {
                let checks = await LocalDomainService.shared.checkSetup(suffix: suffix)
                await MainActor.run {
                    if !Task.isCancelled {
                        setupChecks = checks
                        setupStatusLabel = "Needs attention"
                    }
                    isAutoSetupRunning = false
                    ToastManager.shared.show("Auto setup failed: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }

    private func runSetupCheckOnly(for suffix: String) {
        guard !suffix.isEmpty else { return }
        setupTask?.cancel()
        isAutoSetupRunning = true
        setupStatusLabel = "Checking..."

        setupTask = Task {
            let checks = await LocalDomainService.shared.checkSetup(suffix: suffix)
            await MainActor.run {
                if !Task.isCancelled {
                    setupChecks = checks
                    setupStatusLabel = checks.allSatisfy(\.isPassing) ? "Healthy" : "Needs attention"
                }
                isAutoSetupRunning = false
            }
        }
    }

    private func runAutomaticUnsetup(for suffix: String) {
        guard !suffix.isEmpty else { return }
        setupTask?.cancel()
        isAutoSetupRunning = true
        setupStatusLabel = "Removing..."

        setupTask = Task {
            do {
                let checks = try await LocalDomainService.shared.unsetup(suffix: suffix)
                await MainActor.run {
                    if !Task.isCancelled {
                        setupChecks = checks
                        setupStatusLabel = "Removed"
                        ToastManager.shared.show("Local-domain setup removed for .\(suffix)", type: .success)
                    }
                    isAutoSetupRunning = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    isAutoSetupRunning = false
                    setupStatusLabel = "Cancelled"
                }
            } catch {
                await MainActor.run {
                    isAutoSetupRunning = false
                    setupStatusLabel = "Needs attention"
                    ToastManager.shared.show("Unsetup failed: \(error.localizedDescription)", type: .error)
                }
            }
        }
    }

    private func openDomainIndex() {
        let normalized = normalizedDomainSuffix(containerDomainSuffix)
        guard !normalized.isEmpty else { return }

        let scheme = preferHTTPSDomains ? "https" : "http"
        if let url = URL(string: "\(scheme)://index.\(normalized)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyDomainIndex() {
        let normalized = normalizedDomainSuffix(containerDomainSuffix)
        guard !normalized.isEmpty else { return }

        let scheme = preferHTTPSDomains ? "https" : "http"
        let url = "\(scheme)://index.\(normalized)"
        copyToClipboard(url, message: "Copied \(url)")
    }

    private func copyWorkflowGuide() {
        let suffix = normalizedDomainSuffix(containerDomainSuffix)
        guard !suffix.isEmpty else { return }

        let scheme = preferHTTPSDomains ? "https" : "http"
        let guide = """
        ColimaUI Local Domains - Dev Workflow

        1) Start Colima and open ColimaUI.
        2) Go to Settings > Local Domains and keep it enabled.
        3) Confirm checks are healthy (dnsmasq, resolver, proxy, TLS, index).
        4) Start your app stack:
           docker compose up -d
        5) Use these URLs:
           - Web: \(scheme)://web.<project>.\(suffix)
           - API: \(scheme)://api.<project>.\(suffix)
           - Index: \(scheme)://index.\(suffix)

        How traffic works:
        - Container-to-container: normal Docker networking and internal ports.
        - Browser-to-container: domain -> colimaui-proxy -> container HTTP port.

        If auto port detection is wrong, add this label to that service:
        - dev.colimaui.http-port=8080

        Optional custom domains:
        - dev.colimaui.domains=api.\(suffix),docs.\(suffix)
        """

        copyToClipboard(guide, message: "Copied full dev workflow guide")
    }

    private func copyComposeTemplate() {
        let suffix = normalizedDomainSuffix(containerDomainSuffix)
        guard !suffix.isEmpty else { return }

        let template = """
        services:
          web:
            image: your-web-image
            labels:
              - dev.colimaui.http-port=3000
              # optional: - dev.colimaui.domains=web.myapp.\(suffix)

          api:
            image: your-api-image
            labels:
              - dev.colimaui.http-port=8080
              # optional: - dev.colimaui.domains=api.myapp.\(suffix)

          db:
            image: postgres:16

        # Access from macOS:
        # web.<project>.\(suffix)
        # api.<project>.\(suffix)
        """

        copyToClipboard(template, message: "Copied compose template")
    }

    private func copyToClipboard(_ text: String, message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        ToastManager.shared.show(message, type: .success)
    }

    private var isLocalDomainSetupHealthy: Bool {
        !setupChecks.isEmpty && setupChecks.allSatisfy(\.isPassing)
    }

    private var automaticSetupControls: some View {
        HStack(spacing: 10) {
            if !isLocalDomainSetupHealthy {
                setupActionButton(title: "Run Setup") {
                    runAutomaticSetupAndCheck(for: normalizedDomainSuffix(containerDomainSuffix))
                }
            }

            setupActionButton(title: "Check") {
                runSetupCheckOnly(for: normalizedDomainSuffix(containerDomainSuffix))
            }

            if isLocalDomainSetupHealthy {
                setupActionButton(title: "Unsetup") {
                    runAutomaticUnsetup(for: normalizedDomainSuffix(containerDomainSuffix))
                }
            }

            if isAutoSetupRunning {
                ProgressView()
                    .controlSize(.small)
            }

            Text(setupStatusLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textMuted)
        }
    }

    private var setupPermissionNote: some View {
        Text("Setup may prompt for macOS admin access and can add dnsmasq as a background item on first run.")
            .font(.system(size: 11))
            .foregroundColor(Theme.textMuted)
    }

    private var devWorkflowCopyPack: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Dev Workflow Copy Pack")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                HStack(spacing: 8) {
                    setupActionButton(title: "Copy Full Guide", action: copyWorkflowGuide)
                    setupActionButton(title: "Copy Compose Template", action: copyComposeTemplate)
                }
            }

            Text("Includes a ready-to-paste setup checklist and compose labels for web + api routing.")
                .font(.system(size: 11))
                .foregroundColor(Theme.textMuted)
        }
        .padding(.horizontal, 2)
    }

    private var domainIndexControls: some View {
        HStack(spacing: 8) {
            Button("Open", action: openDomainIndex)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.07))
                .cornerRadius(6)
                .disabled(!enableContainerDomains)

            Button {
                copyDomainIndex()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
                    .padding(7)
                    .background(Color.white.opacity(0.07))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .tooltip("Copy index URL")
            .disabled(!enableContainerDomains)
        }
    }

    private func setupActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.07))
            .cornerRadius(6)
            .disabled(!enableContainerDomains || isAutoSetupRunning)
    }
}

struct SettingsRow<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let control: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()

            control()
        }
    }
}

private struct LocalDomainCheckRow: View {
    let check: LocalDomainCheck

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: check.isPassing ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(check.isPassing ? Theme.statusRunning : Theme.statusWarning)

            VStack(alignment: .leading, spacing: 1) {
                Text(check.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.textPrimary)

                Text(check.detail)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textMuted)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .cornerRadius(8)
    }
}

#Preview {
    SettingsView()
}
