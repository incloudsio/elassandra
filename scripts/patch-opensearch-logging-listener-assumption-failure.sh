#!/usr/bin/env bash
# Echo JUnit assumption failures to stderr (Gradle sometimes reports SKIPPED with no Throwable on TestResult).
set -euo pipefail
DEST="${1:?OpenSearch clone root}"
F="$DEST/test/framework/src/main/java/org/opensearch/test/junit/listeners/LoggingListener.java"
[[ -f "$F" ]] || exit 0

if grep -q 'testAssumptionFailure' "$F" 2>/dev/null; then
  echo "LoggingListener already has testAssumptionFailure → $F"
  exit 0
fi

python3 - "$F" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if "testAssumptionFailure" in text:
    sys.exit(0)
if "import org.junit.runner.notification.Failure" not in text:
    text = text.replace(
        "import org.junit.runner.Description;\n",
        "import org.junit.runner.Description;\nimport org.junit.runner.notification.Failure;\n",
        1,
    )
needle = "    @Override\n    public void testFinished(final Description description) throws Exception {\n        previousLoggingMap = reset(previousLoggingMap);\n    }\n"
if needle not in text:
    print("LoggingListener: could not find testFinished block →", path, file=sys.stderr)
    sys.exit(1)
replacement = """    @Override
    public void testIgnored(final Description description) throws Exception {
        System.err.println("[opensearch-sidecar-elassandra] testIgnored: " + description);
        super.testIgnored(description);
    }

    @Override
    public void testAssumptionFailure(final Failure failure) {
        System.err.println(
            "[opensearch-sidecar-elassandra] AssumptionViolated: "
                + failure.getTestHeader()
                + " — "
                + failure.getMessage()
        );
        final Throwable t = failure.getException();
        if (t != null) {
            t.printStackTrace(System.err);
        }
    }

""" + needle
text = text.replace(needle, replacement, 1)
path.write_text(text, encoding="utf-8")
print("Patched LoggingListener.testAssumptionFailure →", path)
PY
