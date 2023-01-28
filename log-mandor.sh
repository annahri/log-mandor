#!/bin/bash
# Author: Muhammad Ahfas An Nahri <ahfas.annahri@gmail.com>

required_cmds=(
    sendmail
    )

usage() {
    cmd="$(basename "$0")"

    cat <<EOF
$cmd - Monitors a log file and sends an alert when a matching pattern found.
Usage: $cmd <flags>

Mandatory flags:
 -f FILE    
    Log file to monitor
 -t SECONDS 
    Set the alerting grace time
 -p PATTERN 
    Regex pattern to match against the log line

 -T ADDR    
    Specify the recipient email address.
    Also supports this format: Name <address@domain.tld>
 -F ADDR    
    Specify the sender address
    Also supports this format: Name <address@domain.tld>
 -S STRING  
    Email subject for the alert email

Optional flags:
 --add-note NOTES
    Adds additional notes to the end of the alert body

Other flags:
 -s Interactively sets up a systemd service
 -h Show this help info

EOF
    exit 
}

check_requirements() {
    for prog in "${required_cmds[@]}"; do
        if ! command -v "$prog" > /dev/null 2>&1; then
            echo "Command \`$prog\` is required to run this script." >&2
            exit 2
        fi
    done
}

arg_parse() {
    if [[ $# -eq 0 ]]; then
        usage
    fi

    while [[ $# -ne 0 ]]; do case "$1" in
        -p) # Pattern
            match_pattern="$2"
            shift
            ;;
        -f) # Log file
            monitored_logfile="$2"
            shift
            ;;
        -t) # Grace time to send alert
            alert_time="$2"
            shift
            ;;
        -s) # Setup daemon
            setup_daemon
            exit
            ;;
        -h) # Show usage
            usage
            ;;

        -T) # Email to
            alert_recipient="$2"
            shift
            ;;
        -F) # Email from
            alert_sender="$2"
            shift
            ;;
        -S) # Email subject
            alert_subject="$2"
            shift
            ;;
        --add-note) # Adds some notes in the end of the alert body
            notes="$2"
            shift
            ;;

        *) # Invalid options
            echo "Invalid option: $1"
            exit 1
            ;;
    esac; shift; done
}

setup_daemon() {
    if [[ $EUID -ne 0 ]]; then
        echo "This option requires sudo permissions." >&2
        exit 3
    fi

    local name log_path pattern grace_time sender recipient subject service_name

    while true; do
        read -rp "Enter a name for this alerting: " name
        while read -rp "Enter the log file path: " log_path; do
            [[ -f "$log_path" ]] && break
            echo "Log file doesn't exist" >&2
        done
        read -rp "Enter the regex pattern: " pattern
        while read -rp "Enter the alert grace time (in seconds): " grace_time; do
            [[ "$grace_time" =~ [0-9]+ ]] && break
            echo "Invalid input" >&2
        done
        read -rp "Enter the alert sender address: " sender
        read -rp "Enter the alert recipient address: " recipient
        read -rp "Enter your custom alert subject: " subject

        read -rp "Continue (N)?" prompt
        [[ "$prompt" =~ [^Nn] ]] && break
    done
    
    service_name="logmandor-${name}.service"
    service_path="/etc/systemd/system/${service_name}"

    if [[ -f "$service_path" ]]; then
        while read -rp "The alerting with name \"$name\" already exists. What to do ([O]verwrite/[E]xamine/[I]gnore)? " answer; do
            case "$answer" in
                O|o) : nothing ; break ;;
                E|e) "$EDITOR" "$service_path" ;;
                I|i) skip=true; break ;;
                *) continue ;;
            esac
        done
    fi

    if [[ -z "$skip" ]]; then
        cat <<EOF > "$service_path"
[Unit]
Description= LogMonitor - $name

[Service]
ExecStart=$(readlink -f "$0") -f "$log_path" -p "$pattern" -t "$grace_time" -T "$recipient" -F "$sender" -S "$subject"

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemd-analyze verify "$service_path" 2> /dev/null \
        && systemctl daemon-reload \
        && systemctl enable --now "$service_name"
}

compose_email() {
    echo "From: $alert_sender"
    echo "To: $alert_recipient"
    echo "Subject: $alert_subject"
    echo
    echo "Hello,"
    echo 
    echo "A matching log entry has been found:"
    echo 
    echo " Log file: $monitored_logfile"
    echo " Pattern: $match_pattern"
    echo " Timedate: $(date --rfc-email)"
    echo 
    echo " Log line:"
    echo "   $log_line"
    echo
    echo -n "Additional info: "

    if [[ -n "$notes" ]]; then
        echo "$notes"
    else
        echo "n/a"
    fi

    echo 
    echo "Thanks,"
    echo "Log-Mandor Script"
}

send_alert() {
    message_body="$(compose_email)"
    echo "Matched log entry found. Sending alert.." >&2

    pattern='^.*<(.*)>$'

    # Check if the alert_recipient uses the following format:
    #   Sender Name <address@domain.tld>
    # Then capture the email only
    if [[ "$alert_recipient" =~ $pattern ]]; then
        alert_recipient="${BASH_REMATCH[1]}"
    fi

    sendmail "$alert_recipient" <<< "$message_body"
}

main() {
    check_requirements
    arg_parse "$@"

    time_last=0

    while read -r log_line; do
        if [[ "$log_line" =~ $match_pattern ]]; then
            time_now=$(date +%s)
            time_delta=$(( time_now - time_last ))

            [[ $time_delta -lt $alert_time ]] && continue

            send_alert "$log_line"
            time_last=${time_now}
        fi
    done < <(tail -Fn0 "$monitored_logfile")
}

main "$@"
