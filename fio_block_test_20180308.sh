#!/bin/bash

#********************************************************************
#  FileName             : ceph_block_test.sh
#  Author               : zhangxinjia/z00226290
#  history              : first create
#  Date         : 2018/1/29
#  function     : CEPH BLOCK性能测试
#--------------------------------------------------------
# 基础性能测试部分，先不提供；
# 基础性能测试项包括以下几类：
# 1: 1MB 顺序写带宽
# 2: 1MB 顺序读带宽
#  : 低级格式化时间 1st
# 3: 128KB 顺序写带宽
# 4: 128KB 顺序读带宽
# 5: 随机 4KB 写IOPS
# 6: 随机 4KB 读IOPS
# 7: 随机 512B 同步写IOPS (仅当盘卡LBA Sectorsize为512B)
# 8: 随机 4KB 7:3读写混合IOPS
# 9: 随机 4KB 写时延 99%、99.99% Qos
#    随机 4KB 4QD(队列) 写时延 99%、99.99% Qos
#    随机 4KB 128QD(队列) 写时延 99%、99.99% Qos
#10: 随机 4KB 读时延 99%、99.99% Qos
#    随机 4KB 4QD(队列) 读时延 99%、99.99% Qos
#    随机 4KB 128QD(队列) 读时延 99%、99.99% Qos
#11: 随机 4KB 7:3读写混合时延 99%、99.99% Qos
#    随机 4KB 4QD(队列) 7:3读写混合读时延 99%、99.99% Qos
#    随机 4KB 128QD(队列) 7:3读写混合读时延 99%、99.99% Qos
#12: 随机 8KB 写IOPS
#13: 随机 8KB 读IOPS
#--------------------------------------------------------
#按照块测试用例，仅提供以下ext部分测试 ~ ~

#  ：低级格式化时间 2nd
#  ：mkfs.ext4 Trim时间
#  ：高级格式化时间
#  ：mkfs.xfs Trim时间
#  ：设置90%盘片容量时间

#update history: 2016/09/27  增加低格、Trim、高格、设置90%盘片容量时间测试
#————————————————2016/10/25  单线程顺序写带宽测试增加cpumask/cpus_allowed参数绑定CPU、新增ES3600P V3 2.0TB(03032JHD)
#————————————————2016/11/07  根据开发提供《各版本支持盘卡情况1.xlsx》文档刷新盘卡PN码信息
#                            新增C30两盘：ES3600P V3 800GB(03032JGV)/ES3500P V3 800GB(03032JHA)
#                                   两卡：ES3600C V3 800GB(03032JLF)/ES3600C V3 1.2TB(03032BEJ)


#set -x
###echo "Y" | cp ./nvmecli /usr/sbin
#echo "Y" | cp ./fio /usr/sbin

usage()
{
        echo "ceph block performance test shell script current version 2018-01-29"
        echo "`basename $0 `             -[d|r|t|s] args"
        echo "-d <device>                one block device for IO test, like: /dev/nvme0n1"
        echo "-r <runtime(s)>            running time for each test item,like: 3600 second"
        echo "-s <iostat sample>         iostat tool sample time,like: 1"
}



tlog()
{
        time=`date -d today +"%Y-%m-%d %T"`
        echo "[$time] $1" >>$result_dir/fio_run.log
}

while getopts :v:d:r:t:l:s:h:?: OPTION
do
    case $OPTION in
        d)   dev=$OPTARG;;
        r)   runtime=$OPTARG;;
        t)   test_type=$OPTARG;;
        s)   sample=$OPTARG;;
        h)   usage;exit 0;;
        ?)   usage;exit 0;;
   esac
done

if [ "$dev" != "" ]; then
        if [ -b $disk ]; then
                echo "1.device name = $dev"
        else
                echo "Invalid block device $disk, exit!"
                usage
                exit 1
        fi
else
        echo "Invalid block device $disk, exit!"
        usage
        exit 1
fi

#if [ 0 == $vendor ] || [ 1 == $vendor ]
#then
#    dev_Idx=${dev:0-7:5}
#elif [ 2 == $vendor ]
#then
#else
#    dev_Idx=`echo $dev | cut -d "/" -f 3`
#fi

if [ -z $runtime ]; then

        echo "Please specify the running time -r option, exit!"
        usage
        exit 1
fi
echo "2.runtime = $runtime"

if [ -z $sample ]; then
        echo "Please specify the iostat sample time -s option, exit!"
        usage
        exit 1
fi
echo "5.iostat sample = $sample"


dev_Idx=`echo $dev | cut -d "/" -f 3`
disk_size=`fdisk -l $dev | grep "Disk" | awk '{print $3}' | cut -d "." -f 1`
sr=10
cur=$(date +%Y%m%d%H%M%S)

User_Cap_x2=$(($disk_size * 2))
user_cap_90=$((($disk_size / 10) * 9))
unit=GB
unit1=G
write_size=$User_Cap_x2$unit
set_cap_size=$user_cap_90$unit1
T8_Cap=$(($User_Cap_x2 / 8))
T8_Cap_size=$T8_Cap$unit
T8_7W3W_Cap=$(((($User_Cap_x2  / 3) * 10) / 8))
T8_7W3W_Cap_size=$T8_7W3W_Cap$unit

declare -i time_start=0
declare -i time_end=0
declare -i time_used=0

declare -i time_format_1=0
declare -i time_format_2=0
declare -i time_HighFormat=0
# declare -i time_trim_ext4_1=0
declare -i time_trim_ext4_2=0
declare -i time_trim_xfs=0
declare -i time_SetCapacity=0

#nvme_ver=`modinfo nvme | grep version: | awk '{print $2}' | sed -n 1p`

#echo "DUT Info 1:disk_type = $#disk_type"
#echo "DUT Info 2:disk_size(GB) = $disk_size"
#echo "DUT Info 3:Seq Write 2 * Disk Cap Size(GB) = $write_size"
#echo "DUT Info 4:8 Threads Rand Write Size(GB) = $T8_Cap_size"
#echo "DUT Info 5:8 Threads Rand Write 7:3 Write Size(GB) = $T8_7W3W_Cap_size"
#echo "DUT Info 6:SN--$SN"
#echo "DUT Info 7:FW Version--$FW_Ver"
#echo "DUT Info 8:nvme.ko Version--$nvme_ver"

 start_timer(){
        echo -n "Start time :"
        date
        time_start=`date +%s`
 }

 end_timer(){
        echo -n "End time: "
        date
        time_end=`date +%s`
 }

used_time(){
        time_used=$time_end-$time_start
        echo "----------------------------------------------------------------"
        echo "$1 Total uesed time : $time_used s"
        echo "----------------------------------------------------------------"
}

ext_test_IOPS(){

        tlog " --> Start single raw disk extension test... "
        #set config of fio benchmark
        prefix=$dev_Idx
        name=disk
        ioengine_arr=(libaio)
        rwtype_array=(read write)
        #numjobs_arr=(1 4 8 16 32)
        numjobs_arr=(8)
        iodepth_arr=(1 32 64 128)
        #iodepth_arr=(64)
        bs_arr=(4K 8K 32K 64K 128K 256K 512K)
        pretime=3600
        rtime=$2
        etcur=result_et_IOPS_${dev_Idx}_${cur}
        mkdir $etcur
        echo "DUT Info :extend test result directory:etcur = $etcur"


        output=$etcur/ext_result.csv
        #output_psync=$etcur/ext_result_psync.csv
        echo "DISK,RWTYPE,BS,T,QD,R_BW(MB/s),R_IOPS,R_LAT_Avg(us),R_LAT_Max(us),R_LAT_QoS_99.99(us),R_LAT_QoS_99.9(us),R_LAT_QoS_99(us),R_LAT_QoS_90(us),W_BW(MB/s),W_IOPS,W_LAT_Avg(us),W_LAT_Max(us),W_LAT_QoS_99.99(us),W_LAT_QoS_99.9(us),W_LAT_QoS_99(us),W_LAT_QoS_90(us)" |tee -a $output
        #echo "DISK,READ%,BS,T,QD,R_BW(MB/s),R_IOPS,R_LAT_Avg(us),R_LAT_Max(us),R_LAT_QoS_99.99(us),R_LAT_QoS_99.9(us),R_LAT_QoS_99(us),R_LAT_QoS_90(us),W_BW(MB/s),W_IOPS,W_LAT_Avg(us),W_LAT_Max(us),W_LAT_QoS_99.99(us),W_LAT_QoS_99.9(us),W_LAT_QoS_99(us),W_LAT_QoS_90(us)" |tee -a $output_psync


        for bs in ${bs_arr[@]}
        do
                for numjobs in ${numjobs_arr[@]}
                do
                        for iodepth in ${iodepth_arr[@]}
                        do
                                for rwtype in ${rwtype_array[@]}
                                do
                                        #do test
                                        name=${prefix}_${rwtype}R_${iodepth}Q_${numjobs}T_${bs}
                                        tlog "./fio --name=$name --time_based --group_reporting  --numjobs=$numjobs --rw=randrw --direct=1 --ioengine=$ioengine --filename=$filename --bs=${bs} --iodepth=1 --runtime=$rtime --minimal >> ${etcur}/result.log"
                                        mpstat -P ALL $sample 3456 >${etcur}/${name}_mp.log &
                                        free -m -s $sample -c 3456|grep Mem|awk -F " " '{print $3}' >${etcur}/${name}raw_mem.log &
                                        iostat -xmt $sample -p $dev >${etcur}/${name}_io.log &
                                        fio --name=$name --time_based --group_reporting  --numjobs=$numjobs --rw=$rwtype --direct=1 --ioengine=libaio --filename=$dev  --bs=${bs} --iodepth=$iodepth  --runtime=$rtime --random_generator=tausworthe --minimal >> ${etcur}/result.log
                                        pkill iostat
                                        pkill mpstat
                                        pkill free
                                        echo ""
                                        echo "///////////////////////////////////////////////"
                                        tail -n1 ${etcur}/result.log| awk -F ";" '{printf "%s,%s,%s,%d,%d,%d,%d,%.3f,%.3f,%s,%s,%s,%s,%d,%d,%.3f,%.3f,%s,%s,%s,%s\n","'${prefix}'","'$rwtype'","'$bs'","'$numjobs'","'$iodepth'",$7/1024,$8,$40,$39,$32,$34,$30,$28,$48/1024,$49,$81,$80,$75,$73,$71,$69}' | tee -a $output
                                        echo "///////////////////////////////////////////////"

                                done
                        done
                done
        done


        tlog "End single raw disk extension Latency test <-- "

}

main(){


        tlog "Ready to test Disk IO ext_IOPS_test Performance!"
        ext_test_IOPS $dev $runtime
        tlog "End to test Disk IO ext_IOPS_test Performance!"

}

main
