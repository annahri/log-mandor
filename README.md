# Log Mandor

log-mandor.sh is a Bash script which allows you to monitor a log file and sends an alert if the matching pattern found.

```bash
log-mandor.sh - Monitors a log file and sends an alert when a matching pattern found.
Usage: log-mandor.sh <flags>

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

```

## Requirements

1. Bash 5.0 or greater
2. Sendmail
