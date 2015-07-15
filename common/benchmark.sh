#!/bin/sh

set -e

if [ `id -u` -ne  0 ]; then
    echo "You must be root to run this script."
    exit 1
fi

# get the right vmstat command that returns the free memory status
mfree() {
    if test "$os" = "FreeBSD"; then
	vmstat -H | tail -1 | awk '{print $5}'
    elif test "$os" = "Linux"; then
	vmstat | tail -1 | awk '{print $4}'
    fi
}

# generate a random experiment ID used for starting experiments
genEid() {
    echo i`tr -cd 'a-f0-9' </dev/urandom | head -c 5`
}

# start topology with IMUNES
# $1 - eid
# $2 - topology
startTopo() {
    imunes -b -e $1 $2 > start_$1.log
    egrep -o "[0-9]+\.[0-9]+ " start_$1.log
}

# terminate topology with IMUNES
# $1 - eid
termTopo() {
    imunes -b -e $1 > term_$1.log
    egrep -o "[0-9]+\.[0-9]+ " term_$1.log
}

printDockerInfo() {
    srvver=`docker version | grep "Server version:"| cut -d: -f2`
    apiver=`docker version | grep "Server API version:"| cut -d: -f2`
    gitver=`docker version | grep "Git commit (server):"| cut -d: -f2`
    echo "Docker version$srvver (API:$apiver, git:$gitver)"
    docker info 2> /dev/null | grep -A 2 Storage | sed -e 's/^ */\t/'
}

printLinuxHardwareInfo() {
    echo "Hardware info:"
    echo "CPU:`cat /proc/cpuinfo | grep "model name" | head -1 | cut -d: -f2`" | sed -e 's/^/\t/'
    echo "Cores: `cat /proc/cpuinfo | grep processor | wc -l`" | sed -e 's/^/\t/'
    mem_gb=$(echo "scale=2; `cat /proc/meminfo | grep MemTotal | awk '{print $2}'`/1024/1024" | bc -l)
    echo "RAM: $mem_gb GB" | sed -e 's/^/\t/'
}

printFreebsdHardwareInfo() {
    echo "Hardware info:"
    echo "CPU:`sysctl hw.model | cut -d: -f2`" | sed -e 's/^/\t/'
    echo "Cores:`sysctl hw.ncpu | cut -d: -f2`" | sed -e 's/^/\t/'
    mem_gb=$(echo "scale=2; `sysctl hw.realmem | cut -d: -f2`/1024/1024/1024" | bc -l)
    echo "RAM: $mem_gb GB" | sed -e 's/^/\t/'
}

#argument parsing
os=`uname -s`
count=10
wait_before_termination=10
do_sleep=1;

while getopts ":c:i" opt; do
    case $opt in
	c) count=$OPTARG;;
	i) do_sleep=0;;
	\?) echo "Invalid option: -$OPTARG" >&2;;
    esac
done

shift $((OPTIND-1))

tests="$*"

# print system info
uname -srvm
if test "$os" = "FreeBSD"; then
    imunes -i
    printFreebsdHardwareInfo
elif test "$os" = "Linux"; then
    printDockerInfo 
    printLinuxHardwareInfo
else
    echo "OS not supported."
    exit 1
fi

if test "$tests" = ""; then
    echo "No topologies specified... exiting."
    exit 0
fi

echo "Benchmarking topologies: $tests"
echo "Number of iterations: $count"

for t in $tests; do
    echo "Running topology: $t"
    freem_before_bench=`mfree`
    sum_start=0
    sum_term=0
    sum_memusage=0
    for i in $(seq 1 $count); do
	eid=`genEid`
	# measure free memory before
	freem_before=`mfree`
	echo -n "$i. eid: $eid "
	# start topology
	start_time=`startTopo $eid $t`
	echo -n "start: $start_time "
	if test $do_sleep -eq 1; then
	    # wait for topology stabilization
	    sleep $start_time
	    # wait before termination
	    sleep $wait_before_termination
	fi
	# calculate memusage
	freem_after=`mfree`
	if test $i -eq 1; then
	    memusage=0
	else
	    memusage=$(($freem_before-$freem_after))
	    echo -n "memusage: $memusage "
	fi
	# terminate topology
	term_time=`termTopo $eid`
	echo "term: $term_time "
	if test $do_sleep -eq 1; then
	    # wait for system stabilization
	    sleep $term_time
	fi
	freem_end=`mfree`
	# accumulate values for average
	sum_start=`echo $sum_start+$start_time | bc -l`
	sum_term=`echo $sum_term+$term_time | bc -l`
	sum_memusage=`echo $sum_memusage+$memusage | bc -l`
    done
    freem_after_bench=`mfree`
    avg_start=`echo "scale=3; $sum_start/$count" | bc -l`
    avg_term=`echo "scale=3; $sum_term/$count" | bc -l`
    avg_memusage=`echo "scale=0; $sum_memusage/$count" | bc -l`
    echo "Average startup time: $avg_start s"
    echo "Average termination time: $avg_term s"
    echo "Average memory usage: $avg_memusage KB"
    echo "Total memory leak: $(($freem_before_bench-$freem_after_bench)) KB"
done

#cleanup logs
rm -f *log
