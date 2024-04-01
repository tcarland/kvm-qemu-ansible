#!/usr/bin/env bash
#
# Determine guest vm resource totals per host for a given manifest.
# Timothy C. Arland <tcarland@gmail.com>
#
PNAME=${0##*\/}

manifest="$1"
hostonly="$2"

totalsf=".kvm-res_totals"
scan=0

grn='\e[32m\e[1m'
yel='\e[93m'
cyn='\e[96m'
nc='\e[0m'

if ! which jq >/dev/null 2>&1; then
    echo "$PNAME Error: jq is not installed!" >&2
    exit 1
fi

if [ -z "$manifest" ]; then
    echo "$PNAME Error: No json manifest provided!" >&2
    exit 1
fi

hosts=$( jq -r '.[] | .host' $manifest )

# read|create cached host data
if [ ! -e $totalsf ]; then
    for x in $hosts; do
       echo " -> Obtaining stats from $x"
       #totalcpu=$(ssh $x "lscpu -e=cpu -J | jq -r '.cpus | length'") # newer versions of linux-util only >=rhel8
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
    vmspec=$(jq ".[] | select(.host == $hostq)" $manifest)

    cpu=$(echo $vmspec | jq '.vmspecs | map(.vcpus) | add')
    mem=$(echo $vmspec | jq '.vmspecs | map(.memoryGb) | add')

    totalcpu=$(cat $totalsf | grep $x | awk -F, '{ print $2 }')
    totalmem=$(cat $totalsf | grep $x | awk -F, '{ print $3 }')

    availcpu=$(($totalcpu - $cpu))
    availmem=$(echo - | awk "{ print $totalmem - $mem }")

    printf "\n${cyn}%s ${nc}: \n" $x
    printf "  cpus total: ${cyn} $totalcpu ${nc} memory total: ${cyn} $totalmem ${nc} \n"
    printf "  cpus used:  ${yel} $cpu ${nc}  memory used: ${yel} $mem ${nc} \n"
    printf " ------------------------------------------------ \n"
    printf "  cpus avail: ${grn} $availcpu ${nc} memory avail: ${grn} $availmem ${nc} \n"
done

exit 0
