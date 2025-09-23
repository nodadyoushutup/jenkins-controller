import jenkins.model.Jenkins

import hudson.model.Node
import hudson.slaves.DumbSlave
import hudson.slaves.JNLPLauncher
import hudson.slaves.RetentionStrategy
import hudson.slaves.NodeProperty

import org.yaml.snakeyaml.Yaml

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermission
import java.util.EnumSet

// --- Config ---
final File YAML_FILE   = new File("/jenkins/casc_configs/config.yaml")
final File SECRETS_DIR = new File(new File(System.getProperty("user.home")), ".jenkins")

def sanitize = { String s -> (s ?: "").replaceAll(/[^A-Za-z0-9._-]/, "_") }

def ensureSecretsDir = { File dir ->
    try {
        Path p = dir.toPath()
        Files.createDirectories(p)
        // Best-effort POSIX perms: 0700
        try {
            def perms = EnumSet.of(
                PosixFilePermission.OWNER_READ,
                PosixFilePermission.OWNER_WRITE,
                PosixFilePermission.OWNER_EXECUTE
            )
            Files.setPosixFilePermissions(p, perms)
        } catch (Throwable ignore) { /* non-POSIX FS or insufficient perms */ }

        if (!dir.canWrite()) {
            println "[agent-init] WARN: Secrets dir '${dir.absolutePath}' is not writable by the Jenkins process user."
        } else {
            println "[agent-init] Ensured secrets dir: ${dir.absolutePath}"
        }
    } catch (Throwable t) {
        println "[agent-init] ERROR: Could not create secrets dir '${dir.absolutePath}': ${t.message}"
    }
}

def loadAgentsFromYaml = { File f ->
    if (!f.exists()) {
        println "[agent-init] JCasC file not found: ${f.absolutePath}"
        return []
    }
    try {
        def Yaml = org.yaml.snakeyaml.Yaml
        def yaml = new Yaml()
        def data = yaml.load(f.text)
        def nodes = (data?.jenkins?.nodes ?: []) as List

        def agents = []
        nodes.each { n ->
            if (!(n instanceof Map)) return
            def p = n.permanent
            if (!(p instanceof Map)) return

            def name = (p.name ?: "").toString().trim()
            if (!name) return

            agents << [
                name: name,
                remoteFS: (p.remoteFS ?: "/home/jenkins").toString(),
                numExecutors: (p.numExecutors ?: 1) as Integer,
                labelString: (
                    p.labelString ?:
                    (p.labels instanceof List ? p.labels.join(" ") : (p.labels ?: ""))
                ).toString(),
                mode: ((p.mode ?: "NORMAL").toString().toUpperCase() == "EXCLUSIVE")
                        ? Node.Mode.EXCLUSIVE
                        : Node.Mode.NORMAL
            ]
        }
        return agents
    } catch (Throwable t) {
        println "[agent-init] Failed to parse YAML (${t.class.simpleName}: ${t.message})"
        return []
    }
}

def ensureNode = { Map cfg ->
    def j = Jenkins.instance
    def existing = j.getNode(cfg.name)

    if (existing == null) {
        def launcher = new JNLPLauncher()
        def node = new DumbSlave(
            cfg.name,
            "Created by init script",
            cfg.remoteFS,
            cfg.numExecutors.toString(),
            cfg.mode,
            cfg.labelString,
            launcher,
            new RetentionStrategy.Always(),
            new ArrayList<NodeProperty<?>>()
        )
        j.addNode(node)
        println "[agent-init] Created inbound agent '${cfg.name}'"
    } else {
        boolean changed = false
        if (!(existing.getLauncher() instanceof JNLPLauncher)) {
            existing.setLauncher(new JNLPLauncher()); changed = true
        }
        if (existing.getNumExecutors() != cfg.numExecutors) {
            existing.setNumExecutors(cfg.numExecutors); changed = true
        }
        if (existing.getLabelString() != cfg.labelString) {
            existing.setLabelString(cfg.labelString); changed = true
        }
        if (existing.getRemoteFS() != cfg.remoteFS) {
            existing.setRemoteFS(cfg.remoteFS); changed = true
        }
        if (existing.getMode() != cfg.mode) {
            existing.setMode(cfg.mode); changed = true
        }
        if (changed) {
            existing.save()
            Jenkins.instance.save()
            println "[agent-init] Updated agent '${cfg.name}'"
        } else {
            println "[agent-init] Agent '${cfg.name}' already up to date"
        }
    }
}

def waitForComputer = { String name, int timeoutSec = 60 ->
    def j = Jenkins.instance
    for (int i = 0; i < timeoutSec; i++) {
        def node = j.getNode(name)
        def comp = node?.toComputer()
        if (comp != null) return comp
        sleep(1000)
    }
    return null
}

def writeSecret = { String name ->
    def comp = waitForComputer(name, 60)
    if (comp == null) {
        println "[agent-init] WARN: Computer for '${name}' not available after wait; skipping secret"
        return
    }

    String secret
    try {
        secret = comp.jnlpMac
    } catch (Throwable t) {
        println "[agent-init] ERROR: Could not read JNLP secret for '${name}': ${t.message}"
        return
    }
    if (!secret) {
        println "[agent-init] WARN: Empty JNLP secret for '${name}' (is it inbound?)"
        return
    }

    def safe = sanitize(name)
    def out = new File(SECRETS_DIR, "${safe}.secret")

    try {
        if (out.exists()) {
            println "[agent-init] WARN: Secret file '${out.absolutePath}' already exists; replacing it."
        }
        out.text = secret + "\n"

        // Best-effort POSIX perms: 0600
        try {
            def p = EnumSet.of(
                PosixFilePermission.OWNER_READ,
                PosixFilePermission.OWNER_WRITE
            )
            Files.setPosixFilePermissions(out.toPath(), p)
        } catch (Throwable ignore) { /* non-POSIX or restricted FS; continue */ }

        println "[agent-init] Wrote ${out.absolutePath}"
    } catch (Throwable t) {
        println "[agent-init] ERROR: Unable to write secret file '${out.absolutePath}': ${t.message}"
    }
}

println "[agent-init] Starting agent creation from ${YAML_FILE.absolutePath}"

// Ensure ~/.jenkins exists before anything else
ensureSecretsDir(SECRETS_DIR)

def agents = loadAgentsFromYaml(YAML_FILE)
if (!agents) {
    println "[agent-init] No agents found in YAML. Nothing to do."
    return
}

agents.each { cfg ->
    try {
        ensureNode(cfg)
        writeSecret(cfg.name)
    } catch (Throwable t) {
        println "[agent-init] ERROR processing '${cfg.name}': ${t.message}"
    }
}
println "[agent-init] Done."
