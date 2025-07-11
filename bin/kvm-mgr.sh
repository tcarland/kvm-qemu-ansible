#!/usr/bin/env bash
#
#  Creates and manages KVM infrastructure using a JSON manifest.
#
PNAME=${0##*\/}
VERSION="v25.06.20"
AUTHOR="Timothy C. Arland <tcarland@gmail.com>"

pool="default"
srcvm="ubuntu"
srcxml=
manifest=

hostsfile="/etc/hosts"
leasecfg="/etc/dnsmasq.d/kvm-leases"
leasefile="/var/lib/dnsmasq/dnsmasq.leases"

nhost=0
run=0
dryrun=0
delete=1
noprompt=0
action=

# ------------------------------------

version="$PNAME $VERSION"
usage="
Creates and Manages KVM infrastructure from JSON Manifests.

Synopsis:
  $PNAME [options] <action> <manifest.json>

Options:
  -K|--keep-disks    : On 'delete' volumes will kept.
  -h|--help          : Show usage info and exit.
  -H|--hosts <file>  : Hosts file to update. Default is '$hostsfile'.
  -L|--lease <file>  : DnsMasq DHCP lease file. Default is '$leasecfg'.
  -p|--pool  <name>  : Storage pool to use, if not '$pool'.
  -n|--dryrun        : Enable DRYRUN, Nothing is executed.
  -s|--srcvm <name>  : Source VM to clone. Default is '$srcvm'.
  -x|--srcxml <file> : Source XML to define and use as the source VM.
  -X|--noprompt      : Disables interactive prompt on delete.
  -V|--version       : Show version info and exit.

  <action>           : Action to perform: build|start|stop|delete
  <manifest.json>    : Name of the JSON manifest file.

Actions:             (All actions require a manifest file)
  config             : Create a new base config template.
  build              : Build VMs defined by the manifest.
                       Clones a source VM and configures DnsMasq
  start              : Start all VMs in the manifest.
  stop               : Stop all VMs in the manifest.
  delete             : Delete all VMs defined by the manifest.
  dumpxml            : Runs 'dumpxml' across the cluster locally.
                       The XML is saved to \$HOME on the host node.
  sethostname        : Configures VM hostnames, if not using the default
                       source VM ($srcvm), set '--srcvm' accordingly.
  setresources       : Will run setvcpus, setmem and setmaxmem for each
                       VM in the manifest. VM's must be stopped.
"

# ------------------------------------
# The schema consists of an array of HostSpec objects that represent a KVM Node,
# and contains a list of VmSpec Objects defining the VM instances.
schema='
[
    {
        "host" : "host01",
        "vmspecs" : [
            {
                "name" : "kvm01",
                "description" : "template"
                "hostname" : "kvmh01.cluster.internal",
                "ipaddress" : "10.10.20.11",
                "vcpus" : 1,
                "memoryGb" : 1,
                "maxMemoryGb" : 1,
                "numDisks": 0,
                "diskSize" : 0
            },
            {
                "name" : "kvm02",
                "description" : "template"
                "hostname" : "kvmh02.cluster.internal",
                "ipaddress" : "10.10.20.12",
                "vcpus" : 1,
                "memoryGb" : 1,
                "maxMemoryGb" : 1,
                "numDisks": 0,
                "diskSize" : 0
            }
        ]
    },
    {
        "host" : "host02",
        "vmspecs" : [
            {
                "name" : "kvm03",
                "description" : "template"
                "hostname" : "kvmh03.cluster.internal",
                "ipaddress" : "10.10.20.13",
                "vcpus" : 1,
                "memoryGb" : 1,
                "maxMemoryGb" : 1,
                "numDisks": 0,
                "diskSize" : 0
            },
            {
                "name" : "kvm04",
                "description" : "template"
                "hostname" : "kvmh04.cluster.internal",
                "ipaddress" : "10.10.20.14",
                "vcpus" : 1,
                "memoryGb" : 1,
                "maxMemoryGb" : 1,
                "numDisks": 0,
                "diskSize" : 0
            }
        ]
    }
]
'

# ------------------------------------

ask()
{
    local prompt="y/n"
    local default=
    local REPLY=

    while true; do
        if [ "${2:-}" = "Y" ]; then
            prompt="Y/n"
            default="Y"
        elif [ "${2:-}" = "N" ]; then
            prompt="y/N"
            default="N"
        fi

        read -p "$1 [$prompt] " REPLY

        if [ -z "$REPLY" ]; then
            REPLY="$default"
        fi

        case "$REPLY" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac
    done
}

vm_is_defined()
{
    local h="$1"
    local vm="$2"

    exists=$(ssh $h "kvmsh list | grep $vm")

    if [ -n "$exists" ]; then
        return 0
    fi

    return 1
}

vm_is_running()
{
    local h="$1"
    local vm="$2"

    running=$(ssh $h "kvmsh list | grep $vm | awk '{ print $3 }'")

    if [ "$running" == "running" ]; then
        return 0
    fi

    return 1
}

wait_for_host()
{
    local name="$1"
    local rt=1

    if [ -z "$name" ]; then
        echo "$PNAME Error in 'wait_for_host' no target provided." >&2
        return $rt
    fi

    for x in {1..5}; do
        yf=$(ssh $name 'uname -n' 2>/dev/null)
        if [[ $yf == $srcvm ]]; then
            printf "\n -> Host is Alive! \n"
            rt=0
            break
        fi
        printf ". "
        sleep 3
    done

    return $rt
}


# ---------------------------------------------------
# MAIN
#
rt=0

while [ $# -gt 0 ]; do
    case "$1" in
        -K|--keep-disks)
            delete=0
            ;;
        'help'|-h|--help)
            echo "$usage"
            exit 0
            ;;
        -H|--hosts)
            hostsfile="$2"
            shift
            ;;
        -L|--leases)
            leasecfg="$2"
            shift
            ;;
        -n|--dryrun)
            echo " <DRYRUN> enabled"
            dryrun=1
            ;;
        -p|--pool)
            pool="$2"
            shift
            ;;
        -s|--srcvm)
            srcvm="$2"
            shift
            ;;
        -x|--srcxml)
            srcxml="$2"
            shift
            ;;
        -X|--noprompt)
            noprompt=1
            ;;
        'version'|-V|--version)
            echo "$version"
            exit 0
            ;;
        *)
            action="$1"
            manifest="$2"
            shift $#
            ;;
    esac
    shift
done

if [ -z "$action" ]; then
    echo "$usage"
    exit 1
fi


case "$action" in
# --- BUILD
build|create|clone)
    if [ -z "$manifest" ]; then
        echo "KVM Spec JSON not provided." >&2
        echo "$usage"
        exit 1
    fi

    nhosts=$(jq 'length' $manifest 2>/dev/null)
    rt=$?

    if [ $rt -ne 0 ]; then
        echo "$PNAME Error reading JSON, aborting .." >&2
        err=$(jq 'length' $manifest)
        echo "$PNAME: $err"
        exit 1
    fi

    if [ $dryrun -eq 0 ]; then
        echo " -> Copying dnsmasq configurations"
        ( sudo cp $hostsfile ${hostsfile}.bak )
        ( sudo cp $leasecfg ${leasecfg}.new )
        ( sudo cp $leasefile ${leasefile}.new )
    fi

    for (( i=0; i<$nhosts; i++ )); do
        host=$(jq -r ".[$i].host" $manifest)
        num_vms=$(jq ".[$i].vmspecs | length" $manifest)

        if [ -n "$srcxml" ]; then
            echo " -> Defining source VM.."
            echo "( ssh $host 'kvmsh define $srcxml' )"
            if [ $dryrun -eq 0 ]; then
                ( ssh $host "kvmsh define $srcxml" )
            fi
        fi

        for (( v=0; v < $num_vms; v++ )); do
            name=$(jq -r ".[$i].vmspecs | .[$v].name" $manifest)
            hostname=$(jq -r ".[$i].vmspecs | .[$v].hostname" $manifest)
            ipaddr=$(jq -r ".[$i].vmspecs | .[$v].ipaddress" $manifest)
            vcpus=$(jq -r ".[$i].vmspecs | .[$v].vcpus" $manifest)
            mem=$(jq -r ".[$i].vmspecs | .[$v].memoryGb" $manifest)
            maxmem=$(jq -r ".[$i].vmspecs | .[$v].maxMemoryGb" $manifest)
            ndisks=$(jq -r ".[$i].vmspecs | .[$v].numDisks" $manifest)
            dsize=$(jq -r ".[$i].vmspecs | .[$v].diskSize" $manifest)

            if vm_is_defined "$host" "$name"; then
                echo " -> VM '$name' already exists on host '$host', Skipping..."
            else
                # Create VM
                echo " -> Create Virtual Machine: '$name'"
                echo "( ssh $host 'kvmsh --pool $pool clone $srcvm $name' )"
                echo "( ssh $host 'kvmsh setmaxmem ${maxmem}G $name' )"
                echo "( ssh $host 'kvmsh setmem ${mem}G $name' )"
                echo "( ssh $host 'kvmsh setvcpus $vcpus $name' )"
                if [ $ndisks -gt 0 ]; then
                    echo "( ssh $host 'kvmsh -D $ndisks -d ${dsize}G attach-disk $name' )"
                fi
                echo ""

                if [ $dryrun -eq 0 ]; then
                    ( ssh $host "kvmsh --pool $pool clone $srcvm $name" )
                    rt=$?

                    if [ $rt -gt 0 ]; then
                        echo "$PNAME Error in clone of $name" >&2
                        exit 1
                    fi

                    ( ssh $host "kvmsh setmaxmem ${maxmem}G ${name}" )
                    ( ssh $host "kvmsh setmem ${mem}G ${name}" )
                    ( ssh $host "kvmsh setvcpus ${vcpus} ${name}" )

                    # Attach Disks
                    if [ $ndisks -gt 0 ]; then
                        ( ssh $host "kvmsh -D $ndisks -d ${dsize}G attach-disk $name" )
                    fi
                fi
            fi

            echo " -> Configure dnsmasq lease. "
            if [ $dryrun -eq 0 ]; then
                mac=$(ssh $host "kvmsh mac-addr $name 2>/dev/null")

                if [ -z "$mac" ]; then
                    echo "$PNAME Error determining MAC Address for '$name'" >&2
                    rt=3
                    break
                fi

                # remove old entry from active leases and lease config
                ( sudo sed -i'' /$ipaddr/d ${leasecfg}.new )
                ( sudo sed -i'' /$ipaddr/d ${leasefile}.new )
                # apply new lease
                ( sudo bash -c "printf 'dhcp-host=%s,%s \n' ${mac} ${ipaddr} >> ${leasecfg}.new" )

                # replace hosts entry
                ( sudo sed -i'' /$ipaddr/d $hostsfile )
                ( sudo bash -c "printf '%s \t %s \t %s\n' $ipaddr $hostname $name >> $hostsfile" )
            fi
        done
    done

    # restart dnsmasq
    echo " -> Restarting DnsMasq"
    if [ $dryrun -eq 0 ]; then
        ( sudo systemctl stop dnsmasq )
        ( sudo mv ${leasecfg}.new $leasecfg )
        ( sudo mv ${leasefile}.new $leasefile )
        ( sudo systemctl restart dnsmasq )
    fi
    ;;

# --- START
start)
    if [ -z "$manifest" ]; then
        echo "$PNAME Error: JSON manifest not provided." >&2
        echo "$usage"
        exit 1
    fi

    nhosts=$(jq 'length' $manifest)

    for (( i=0; i<$nhosts; i++ )); do
        host=$(jq -r ".[$i].host" $manifest)
        num_vms=$(jq ".[$i].vmspecs | length" $manifest)

        for (( v=0; v < $num_vms; v++ )); do
            name=$(jq -r ".[$i].vmspecs | .[$v].name" $manifest)

            echo "( ssh $host 'kvmsh start $name' )"
            if [ $dryrun -eq 0 ]; then
                ( ssh $host "kvmsh start $name" )
                ( sleep 1 )
            fi
        done
    done
    ;;

# --- SET HOSTNAME
sethostname*)
    echo " -> Setting hostnames for '$manifest'"

    # Get the last vm in the set
    nhosts=$(jq 'length' $manifest)
    (( nlast=$nhosts-1 ))
    nvms=$(jq ".[$nlast].vmspecs | length" $manifest)
    (( nvms=$nvms-1 ))
    host=$(jq -r ".[$nlast].host" $manifest)
    lastvm=$(jq -r ".[$nlast].vmspecs | .[$nvms].name" $manifest)

    # Validate the vm has been started.
    ( ssh $host "kvmsh status $lastvm" )
    rt=$?
    if [ $rt -ne 0 ]; then
        echo "$PNAME Error: Hosts appears off, run 'start' first?" >&2
        exit $rt
    fi

    # Wait for the vm to respond to logins
    printf " -> Waiting for the last host, '%s' to respond . . " $lastvm
    ( sleep 5 )
    if [ $dryrun -eq 0 ]; then
        wait_for_host "$lastvm"
        rt=$?
    fi
    echo ""

    if [ $rt -ne 0 ]; then
        echo "$PNAME Error waiting for host, no response or request timed out" >&2
        exit 1
    fi

    # set hostnames
    for (( i=0; i<$nhosts; i++ )); do
        num_vms=$(jq ".[$i].vmspecs | length" $manifest)

        for (( v=0; v < $num_vms; v++ )); do
            name=$(jq -r ".[$i].vmspecs | .[$v].name" $manifest)
            hostname=$(jq -r ".[$i].vmspecs | .[$v].hostname" $manifest)

            echo "( ssh $name 'sudo hostname $hostname' )"
            echo "( ssh $name \"sudo bash -c 'echo $hostname > /etc/hostname'\" )"
            if [ $dryrun -eq 0 ]; then
                ( ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "$hostname" > /dev/null 2>&1 )
                ( ssh -oStrictHostKeyChecking=accept-new $name "sudo hostname $hostname" >/dev/null 2>&1 )
                rt=$?
                if [ $rt -gt 0 ]; then
                    ( ssh -oStrictHostKeyChecking=no $name "sudo hostname $hostname" >/dev/null 2>&1 )
                fi
                ( ssh $name "sudo bash -c 'echo $hostname > /etc/hostname'" )
            fi
        done
    done
    ;;

# --- STOP
stop|destroy)
    if [ -z "$manifest" ]; then
        echo "$PNAME Error: JSON manifest not provided." >&2
        echo "$usage"
        exit 1
    fi

    nhosts=$(jq 'length' $manifest)

    for (( i=0; i<$nhosts; i++ )); do
        host=$(jq -r ".[$i].host" $manifest)
        num_vms=$(jq ".[$i].vmspecs | length" $manifest)

        for (( v=0; v < $num_vms; v++ )); do
            name=$(jq -r ".[$i].vmspecs | .[$v].name" $manifest)

            echo "( ssh $host 'kvmsh stop $name' )"
            if [ $dryrun -eq 0 ]; then
                ( ssh $host "kvmsh stop $name" )
                rt=$?
            fi
        done
    done
    ;;

# --- DELETE all VMS
delete)
    if [ -z "$manifest" ]; then
        echo "$PNAME Error: JSON manifest not provided." >&2
        echo "$usage"
        exit 1
    fi

    nhosts=$(jq 'length' $manifest)

    if [ $dryrun -eq 0 ] && [ $noprompt -eq 0 ]; then
        echo "WARNING! 'delete' action will remove all VM's!"
        echo "    (Consider testing with --dryrun option) "
        echo ""

        if [ $delete -eq 0 ]; then
            echo "NOTE --keep-disks enabled. Volumes will not be deleted."
            echo ""
        fi
        ask "Are you certain you wish to continue? " "N"

        if [ $? -ne 0 ]; then
            echo "Aborting delete operation.."
            exit 1
        fi
    fi

    for (( i=0; i<$nhosts; i++ )); do
        host=$(jq -r ".[$i].host" $manifest)
        num_vms=$(jq ".[$i].vmspecs | length" $manifest)

        for (( v=0; v < $num_vms; v++ )); do
            name=$(jq -r ".[$i].vmspecs | .[$v].name" $manifest)
            volumes=()

            xml=$(ssh $host "kvmsh dumpxml $name")
            volumes=$(echo $xml | xmllint --xpath '//disk/source/@file' - 2>/dev/null)

            # kvmsh delete will run stop first
            echo "( ssh $host 'kvmsh delete $name' )"
            if [ $dryrun -eq 0 ]; then
                ( ssh $host "kvmsh delete $name" )
                rt=$?
            fi

            if [ $delete -eq 1 ]; then
                for vol in $volumes; do
                    vol=$(echo $vol | awk -F= '{ print $2 }' | awk -F\" '{ print $2 }')
                    fname="$vol"
                    vol=${vol##*\/}
                    echo "( ssh $host 'kvmsh vol-delete $vol' )"
                    if [ $dryrun -eq 0 ]; then
                        ( ssh $host "kvmsh vol-delete $vol" )
                        rt=$?
                        if [ $rt -ne 0 ]; then
                            echo "$PNAME Error in 'vol-delete', attempting manual cleanup.." >&2
                            echo "( ssh $host 'rm $fname' )"
                            ( ssh $host "rm $fname" )
                        fi
                    fi
                done
            fi
        done
    done
    ;;

# --- EXPORT
dumpxml)
    if [ -z "$manifest" ]; then
        echo "$PNAME Error: JSON manifest not provided." >&2
        echo "$usage"
        exit 1
    fi

    nhosts=$(jq 'length' $manifest)

    for (( i=0; i<$nhosts; i++ )); do
        host=$(jq -r ".[$i].host" $manifest)
        num_vms=$(jq ".[$i].vmspecs | length" $manifest)

        for (( v=0; v < $num_vms; v++ )); do
            name=$(jq -r ".[$i].vmspecs | .[$v].name" $manifest)

            echo "( ssh $host 'kvmsh dumpxml $name > ${name}.xml' )"
            if [ $dryrun -eq 0 ]; then
                ( ssh $host "kvmsh dumpxml $name > ${name}.xml" )
                rt=$?
            fi
        done
    done
    ;;

# --- SETRESOURCES
setresource*)
    if [ -z "$manifest" ]; then
        echo "$PNAME Error: JSON manifest not provided." >&2
        echo "$usage"
        exit 1
    fi

    nhosts=$(jq 'length' $manifest)

    for (( i=0; i<$nhosts; i++ )); do
        host=$(jq -r ".[$i].host" $manifest)
        num_vms=$(jq ".[$i].vmspecs | length" $manifest)

        for (( v=0; v < $num_vms; v++ )); do
            name=$(jq -r ".[$i].vmspecs | .[$v].name" $manifest)
            vcpus=$(jq -r ".[$i].vmspecs | .[$v].vcpus" $manifest)
            mem=$(jq -r ".[$i].vmspecs | .[$v].memoryGb" $manifest)
            maxmem=$(jq -r ".[$i].vmspecs | .[$v].maxMemoryGb" $manifest)

            if vm_is_running "$host" "$name"; then
                echo " -> VM appears to be running, please stop first. Skipping '$name'.." >&2
                continue
            fi

            echo "( ssh $host 'kvmsh setvcpus $vcpus $name' )"
            echo "( ssh $host 'kvmsh setmaxmem ${maxmem}G $name' )"
            echo "( ssh $host 'kvmsh setmem ${mem}G $name' )"
            if [ $dryrun -eq 0 ]; then
                ( ssh $host "kvmsh setvcpus $vcpus $name" )
                ( ssh $host "kvmsh setmaxmem ${maxmem}G $name" )
                ( ssh $host "kvmsh setmem ${mem}G $name" )
            fi
        done
    done
    ;;

config)
    if [ -z "$manifest" ]; then
        echo "$PNAME Error: JSON manifest not provided." >&2
        echo "$usage"
        exit 1
    fi

    if [ -e $manifest ]; then
        echo "$PNAME Error: Cannot write config, manifest '$manifest' already exists." >&2
        exit 2
    fi

    echo "$schema" > $manifest
    echo " -> Created a new configuration template as '$manifest'"
;;


*)
    echo "$PNAME Error: Action '$action' not recognized" >&2
    rt=1
    ;;
esac

echo "$PNAME Finished."

exit $rt
