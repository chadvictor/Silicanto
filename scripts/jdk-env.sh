# Find the JDK, including on macOS where /usr/bin/java may only be a launcher.
if [[ -z "${JAVA_HOME:-}" ]]; then
  if [[ -x "$root/.toolchain/jdk/bin/javac" ]]; then
    JAVA_HOME="$root/.toolchain/jdk"
  else
    JAVA_HOME=$(java -XshowSettings:properties -version 2>&1 | sed -n 's/^ *java.home = //p') || true
  fi
fi
if [[ -z "${JAVA_HOME:-}" || ! -x "$JAVA_HOME/bin/javac" ]]; then
  echo "Set JAVA_HOME to a JDK 17 or newer." >&2; exit 1
fi
jver=$("$JAVA_HOME/bin/javac" -version | awk '{print $2}' | cut -d. -f1)
if [[ ! "$jver" =~ ^[0-9]+$ || "$jver" -lt 17 ]]; then
  echo "Java builds require JDK 17 or newer." >&2; exit 1
fi
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
