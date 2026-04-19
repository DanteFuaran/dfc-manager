#!/bin/sh
cd /opt 2>/dev/null || cd / 2>/dev/null || true
exec /usr/local/dfc-manager/dfc-manager.sh "$@"
