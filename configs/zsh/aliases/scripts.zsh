# Generic environment helpers for repos carrying embedded setup wrappers.
env-install() {
  if [[ -x "./scripts/setup/env-install.sh" ]]; then
    ./scripts/setup/env-install.sh "$@"
  else
    echo "No ./scripts/setup/env-install.sh in current repo."
    return 1
  fi
}

env-update() {
  if [[ -x "./scripts/setup/env-update.sh" ]]; then
    ./scripts/setup/env-update.sh "$@"
  else
    echo "No ./scripts/setup/env-update.sh in current repo."
    return 1
  fi
}
