#!/bin/bash
VMS="Win11-FOG-Deploy:5902 Win11-Golden:5901"
BASE_PORT=6080

case "$1" in
    start)
        for vm in $VMS; do
            name=${vm%:*}
            vnc_port=${vm#*:}
            ws_port=$((BASE_PORT + vnc_port - 5900))
            nohup websockify --web /usr/share/novnc $ws_port localhost:$vnc_port > /var/log/novnc-$name.log 2>&1 &
            echo "Started noVNC for $name on port $ws_port (VNC $vnc_port)"
        done
        echo "All noVNC proxies started"
        ;;
    stop)
        pkill -f "websockify.*/usr/share/novnc" 2>/dev/null || true
        echo "Stopped all noVNC proxies"
        ;;
    status)
        pgrep -af "websockify.*/usr/share/novnc" 2>/dev/null || echo "No noVNC proxies running"
        ;;
    restart)
        $0 stop
        sleep 1
        $0 start
        ;;
    *)
        echo "Usage: $0 start|stop|status|restart"
        exit 1
        ;;
esac
