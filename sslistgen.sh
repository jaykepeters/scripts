#!/bin/bash
# SafeSearch List Generator
# Created by Jayke Peters
## Output Redirection
## Define Global Variables
## ENABLE IN PIHOLE?
ENABLE=True
RELOAD_PIHOLE=True

me=`basename "$0"`
version="1.2"
file="/tmp/safesearch.txt"
conf="/etc/dnsmasq.d/05-restrict.conf"
hosts="/etc/hosts"
url="https://www.google.com/supported_domains"

## Logging Variables
log="/var/log/${me}.log"
maxRuns=10

## Arrays
bingSS=(
    cname=bing.com,strict.bing.com
    cname=www.bing.com,strict.bing.com
)

ssHosts=(
    "############## DO NOT DELETE ##############"
    "216.239.38.120 forcesafesearch.google.com"
    "204.79.197.220 strict.bing.com"
    "############## DO NOT DELETE ##############"
)

## Setup Logging
exec 2>>$log
logger() {
    write() {
        echo [`date '+%Y-%m-%d %H:%M:%S:%3N'`]: "$*" >> $log
    }

    print() {
        echo [`date '+%Y-%m-%d %H:%M:%S:%3N'`]: "$*"
    }

    all() {
        write "$*" 
        print "$*"
    }

    pass() {
        echo "$*"
    }

    error() {
        write "$*"
        pass "$*"
    }

    begin() {
        # Enforce Run Count
        runNum=$(cat $log | grep 'STARTED' | wc -l)
        if [ $runNum == $maxRuns ]; then
            print FLUSHING LOG
            rm -rf $log
        fi
        write STARTED 
    }

    end() {
        write STOPPED
        # https://wtanaka.com/node/7719
        end=$(cat $log|awk '{print length}'|sort -nr|head -1)
        # https://stackoverflow.com/questions/5349718/how-can-i-repeat-a-character-in-bash
        line=$(for ((i=1; i<=$end; i++)); do echo -n =; done)
        pass $line >> $log
    }

    # Take Input
    "$@"
}

## START LOGGING EVERYTHING
logger begin

silently() {
    "$@" &>/dev/null
}

preCheck() {
    # Is there an old file?
    if [ -f "$file" ]; then
        logger all Removing "$file"
        rm "$file"
    fi
}

generate() {
    # Download List into an Array
    logger all Retrieving List from Google
    domains=($(curl $url 2>/dev/null))

    # Append File Header
    echo "# $file generated on $(date '+%m/%d/%Y %H:%M') by $(hostname)" >> "${file}"
    echo "# Google SafeSearch Implementation" >> "${file}" 

    # Generate list of domains
    for domain in "${domains[@]}"; do
        dom=$(echo $domain | cut -c 2-)
        echo cname=$dom,forcesafesearch.google.com >> "${file}"
        echo cname="www""$domain",forcesafesearch.google.com >> "${file}"
    done

    # Notify User of Number of Domains
    count=$(cat $file | grep 'forcesafesearch.google.com' | wc -l)
    total=$(($count * 2))
    logger all ''$count' TLDs'
    logger all ''$total' Domains'

    # Bing Strict Setting
    for line in "${bingSS[@]}"
        do echo "$line"  >> "${file}"
    done
    
    # Enable In Hosts and Pi-hole
    if [ "$ENABLE" == "True" ]; then
        logger all 'ENABLING SAFESEARCH FOR PI-HOLE'
        if [ -f "$conf" ]; then
            rm -Rf "$conf"
        else
            cp -R "$file" "$conf"
        fi
        for host in "${ssHosts[@]}"; do 
            if ! grep -Fxq "$host" "$hosts"; then
                echo "$host" >> "$hosts"
            fi
        done
    fi

    if [ "$RELOAD_PIHOLE" == "True" ]; then
        logger all 'RELOADING HOSTS CONFIGURATION'
        service networking reload
        logger all 'RELOADING PIHOLE FTL'
        service pihole-FTL reload
    fi
}

main() {
    preCheck
    generate
}

quiet() {
    silently main
}

web() {
    silently main
    logger pass $file
}

help() {
    # Log Invalid Arguments
    if [ ! -z "$*" ]; then
        # https://linuxconfig.org/how-do-i-print-all-arguments-submitted-on-a-command-line-from-a-bash-script
        args=("$@") 
        logger error INVALID ARGUMENT: "${args[@]}" 
        sleep 1
        clear
    fi
    # Print Usage Information
    clear
    logger pass "$me version $version
    Usage: $me [options]
    Example: '$me --web'
    
    -w, --web     For use with PHP Script
    -s, --silent  Execute Script Silently
    -h, --help    Display this help message"
}

## Check for user input
if [[ $# = 0 ]]; then
    main
else
    logger write "ARGUMENTS: $1"
    case "${1}" in
        *w | *web     ) web;;
        *s | *silent* ) quiet;;
        *h | *help    ) help;;
        *             ) help "$@";;
    esac
fi

## STOP LOGGING EVERYTHING
logger end
