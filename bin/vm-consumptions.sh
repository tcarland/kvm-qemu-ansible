#!/usr/bin/env bash
#
# Determine guest vm resource totals per host for a given manifest.
#
# Timothy C. Arland <tcarland@gmail.com, tarland@trace3.com>
#
PNAME=${0##*\/}

manifest="$1"
hostonly="$2"

totalsf=".kvm-res_totals"
scan=0

C_GRN='\e[32m\e[1m'
C_YEL='\e[93m'
C_CYN='\e[96m'
C_NC='\e[0m'


if [ -z "$manifest" ]; then
    echo "$PNAME Error: No json manifest provided!"
    exit 1
fi

hosts=$( jq -r '.[] | .host' $manifest )

# read|create cached host data
if [ ! -e $totalsf ]; then
    for x in $hosts; do
       echo " -> Obtaining stats from $x"
       #totalcpu=$(ssh $x "lscpu -e=cpu -J | jq -r '.cpus | length'") # newer versions of linux-util only
       totalcpu=$(ssh $x "lscpu -e=cpu | tail -1")
       totalcpu=$(($totalcpu + 1))
       totalmem=$(ssh $x "lsmem --summary=only" | \
         grep 'Total online' | \
         awk -F: '{ print $2 }' | \
         sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//' | \
         sed 's/G$//' )
       printf "%s,%s,%s \n" $x $totalcpu $totalmem
       printf "%s,%s,%s \n" $x $totalcpu $totalmem >> $totalsf
    done
fi

for x in $hosts; do
    if [ -n "$hostonly" ]; then
        if [[ $hostonly != ${x%%\.*} ]]; then
            continue
        fi
    fi
    hostq="\"$x\""
    vmspec=$( jq ".[] | select(.host == $hostq)" $manifest )

    cpu=$(echo $vmspec | jq '.vmspecs | map(.vcpus) | add')
    mem=$(echo $vmspec | jq '.vmspecs | map(.memoryGb) | add')

    totalcpu=$(cat $totalsf | grep $x | awk -F, '{ print $2 }')
    totalmem=$(cat $totalsf | grep $x | awk -F, '{ print $3 }')

    availcpu=$(($totalcpu - $cpu))
    availmem=$( echo - | awk "{ print $totalmem - $mem }" )

    printf "\n${C_CYN}%s ${C_NC}: \n" $x
    printf "  cpus total: ${C_CYN} $totalcpu ${C_NC} memory total: ${C_CYN} $totalmem ${C_NC} \n"
    printf "  cpus used:  ${C_YEL} $cpu ${C_NC}  memory used: ${C_YEL} $mem ${C_NC} \n"
    printf " ------------------------------------------------ \n"
    printf "  cpus avail: ${C_GRN} $availcpu ${C_NC} memory avail: ${C_GRN} $availmem ${C_NC} \n"

done


exit 0
