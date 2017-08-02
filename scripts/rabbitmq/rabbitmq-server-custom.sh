#!/bin/sh
. /etc/init.d/functions
PATH=/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/erlang/bin
NAME=rabbitmq-server
DAEMON=/usr/sbin/${NAME}
CONTROL=/usr/sbin/rabbitmqctl
DESC=rabbitmq-server
USER=rabbitmq
ROTATE_SUFFIX=
INIT_LOG_DIR=/data/log
PID_FILE=/var/run/rabbitmq/pid
START_PROG="daemon"
LOCK_FILE=/var/lock/subsys/$NAME
test -x $DAEMON || exit 0
test -x $CONTROL || exit 0
RETVAL=0
set -e
[ -f /etc/default/${NAME} ] && . /etc/default/${NAME}
[ -f /etc/sysconfig/${NAME} ] && . /etc/sysconfig/${NAME}
ensure_pid_dir () {
    PID_DIR=`dirname ${PID_FILE}`
    if [ ! -d ${PID_DIR} ] ; then
        mkdir -p ${PID_DIR}
        chown -R ${USER}:${USER} ${PID_DIR}
        chmod 755 ${PID_DIR}
    fi
}
remove_pid () {
    rm -f ${PID_FILE}
    rmdir `dirname ${PID_FILE}` || :
}
start_rabbitmq () {
    status_rabbitmq quiet
    if [ $RETVAL = 0 ] ; then
        echo RabbitMQ is currently running
    else
        RETVAL=0
        # RABBIT_NOFILES_LIMIT from /etc/sysconfig/rabbitmq-server is not handled
        # automatically
        if [ "$RABBITMQ_NOFILES_LIMIT" ]; then
                ulimit -n $RABBITMQ_NOFILES_LIMIT
        fi
        ensure_pid_dir
        set +e
        RABBITMQ_PID_FILE=$PID_FILE $START_PROG $DAEMON \
            > "${INIT_LOG_DIR}/startup_log" \
            2> "${INIT_LOG_DIR}/startup_err" \
            0<&- &
        $CONTROL wait $PID_FILE >/dev/null 2>&1
        RETVAL=$?
        set -e
        case "$RETVAL" in
            0)
                echo SUCCESS
                if [ -n "$LOCK_FILE" ] ; then
                    touch $LOCK_FILE
                fi
                exit 0
                ;;
            *)
                remove_pid
                echo FAILED - check ${INIT_LOG_DIR}/startup_\{log, _err\}
                RETVAL=1
                exit 1
                ;;
        esac
    fi
}
stop_rabbitmq () {
    status_rabbitmq quiet
    if [ $RETVAL = 0 ] ; then
        set +e
        $CONTROL stop ${PID_FILE} > ${INIT_LOG_DIR}/shutdown_log 2> ${INIT_LOG_DIR}/shutdown_err
        RETVAL=$?
        set -e
        if [ $RETVAL = 0 ] ; then
            remove_pid
            if [ -n "$LOCK_FILE" ] ; then
                rm -f $LOCK_FILE
            fi
            exit 0
        else
            echo FAILED - check ${INIT_LOG_DIR}/shutdown_log, _err
            exit 1
        fi
    else
        echo RabbitMQ is not running
        RETVAL=0
    fi
}
status_rabbitmq() {
    set +e
    if [ "$1" != "quiet" ] ; then
        $CONTROL status 2>&1
    else
        $CONTROL status > /dev/null 2>&1
    fi
    if [ $? != 0 ] ; then
        RETVAL=3
    fi
    set -e
}
rotate_logs_rabbitmq() {
    set +e
    $CONTROL rotate_logs ${ROTATE_SUFFIX}
    if [ $? != 0 ] ; then
        RETVAL=1
    fi
    set -e
}
restart_running_rabbitmq () {
    status_rabbitmq quiet
    if [ $RETVAL = 0 ] ; then
        restart_rabbitmq
    else
        echo RabbitMQ is not runnning
        RETVAL=0
    fi
}
restart_rabbitmq() {
    stop_rabbitmq
    start_rabbitmq
}
case "$1" in
    start)
        echo -n "Starting $DESC: "
        start_rabbitmq
        echo "$NAME."
        ;;
    stop)
        echo -n "Stopping $DESC: "
        stop_rabbitmq
        echo "$NAME."
        ;;
    status)
        status_rabbitmq
        ;;
    rotate-logs)
        echo -n "Rotating log files for $DESC: "
        rotate_logs_rabbitmq
        ;;
    force-reload|reload|restart)
        echo -n "Restarting $DESC: "
        restart_rabbitmq
        echo "$NAME."
        ;;
    try-restart)
        echo -n "Restarting $DESC: "
        restart_running_rabbitmq
        echo "$NAME."
        ;;
    *)
        echo "Usage: $0 {start|stop|status|rotate-logs|restart|condrestart|try-restart|reload|force-reload}" >&2
        RETVAL=1
        ;;
esac
exit $RETVAL

