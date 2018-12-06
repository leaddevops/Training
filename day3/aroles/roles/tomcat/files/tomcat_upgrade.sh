#!/bin/bash
#Varables 
envidx=0
inptfile=$1
#root_dir is location os symbolic link creation. Options on Jenkins /app, /var ,/opt
root_dir=$2
enforce=${3:-noforce}


# Validation section
if [ $# -lt 1 ]; then
   echo "Usage: tomcat_upgrade.sh <inputfile> "
   exit 4
fi

if [ ! -f ${inptfile} ]; then
   echo "Input fiel is not available "
   exit 8
fi

username=`whoami`
if [ "$username" != "root" ]; then
   echo "This script need to be run as root - $username does not have adequate authority" 
   exit 8
fi

function statsmessage()
{
message=$1
status=$2

messageLen=${#message}
printf '%s' "$message"
let dashLen=80-messageLen
eval printf '%.0s-' {1..$dashLen}
printf '%s\n' ${status}

}

#Utility
# numeric_cmp()
# Input: lhs(integer) rhs(integer)
# Returns: 0 if lhs == rhs; 2 if lhs < rhs; 3 if lhs > rhs; 1 if error
# Use:     Default comparison function. See the "Use" for compare().
numeric_cmp() {
	(( $1 -eq $2 )) && return 0
	(( $1 -lt $2 )) && return 2
	(( $1 -gt $2 )) && return 3
}

##
# lexical_cmp()
# Input:   lhs(string) rhs(string)
# Returns: 0 if lhs == rhs; 2 if lhs < rhs; 3 if lhs > rhs; 1 if error
# Use:     Example lexical (alphabetical) comparison function.
#          See the "Use" for compare().
lexical_cmp() {
	[[ $1 == $2 ]] && return 0
	[[ $1 <  $2 ]] && return 2
	[[ $1  > $2 ]] && return 3
}


# compare():
# Input:   lhs rhs
# Returns: 0 if lhs == rhs; 2 if lhs < rhs; 3 if lhs > rhs; 1 if error
# Use:     Define this function in order to tell the below functions how to
#          compare values. If you don't define it, numeric_cmp will be
#          assumed.
if ! declare -f compare > /dev/null; then
	compare() {
		lexical_cmp "$@"
	}
fi

##
# qsort():  (Quick sort)
# Average:
# Stability:
# Uses:
qsort() {
	SORTEDARRAY=("$@")
	qsort_recurse 0 $((${#@}-1))	
}
qsort_recurse() {
	local -i l r m i j k # left, right, mid bounds and some iterators
	local part temp      # partition value and temporary storage
	(( l=i=$1, r=j=$2, m=(l+r)/2 ))
	part="${SORTEDARRAY[m]}"
	while ((j > i)); do
		while [[ 1 ]]; do
			compare "${SORTEDARRAY[i]}" "$part"
			(( $? == 2 && i++ )) || break
		done
		while [[ 1 ]]; do
			compare "${SORTEDARRAY[j]}" "$part"
			(( $? == 3 && j-- )) || break
		done
		if (( i <= j )); then
			temp="${SORTEDARRAY[i]}"
			SORTEDARRAY[i]="${SORTEDARRAY[j]}"
			SORTEDARRAY[j]="$temp"
			(( i++, j-- ))
		fi
	done
	(( l<j )) && qsort_recurse $l $j
	(( r>i )) && qsort_recurse $i $r
}

##
#getngarray(): Simulate two dimensional array
getngarray()
{ 
b="${nodegroup[$1]}";
eval "c=$b";
echo "${c[$2]}";
return 0;
};

##
#Recurssively change path permmission
chmodpath(){
chmod $1 $2
mod=$1
if [ -d $2 ]; then
   newdir=${2%/*}
   if [ ${#newdir} -gt 1 ]; then
      chmodpath $mod $newdir
   fi
fi
}

#Read from cntl file
while read line
do
   cntlarray=( ` echo $line | tr "=" " " ` )
   serverlist[i]=${cntlarray[0]}
   i=$(( $i + 1 ))
   
   recordtype=( `echo ${cntlarray[0]} | tr "." " " `)

   case ${recordtype[0]} in
   environment) 
        envname[$envidx]=${recordtype[1]//\"/}
        envvalue[$envidx]=${cntlarray[1]//\"/}
        (( envidx += 1 )) 
	;;
   instance)
        index=${recordtype[1]}
        case ${recordtype[2]} in
          name)     name[$index]=${cntlarray[1]//\"/};;
          location) location[$index]=${cntlarray[1]//\"/};;
          portbase) portbase[$index]=${cntlarray[1]//\"/};;
          javaopts) javaopts[$index]=${cntlarray[@]:1};; 
          *)        echo "unknwon instance variable ${recordtype[2]} - process abort"
                    exit 8
                    ;;     
        esac    
	;;
   \#*)
     	#echo "comment type"
        #echo ${recordtype[0]}
	;;
   *)
     	#echo "unknown type"
        #echo ${recordtype[0]}
        ;;
   esac

done < $inptfile


#Parsing blueprint

envctr=${#envname[@]}
for (( i=0 ; i < ${envctr} ; i++ ))
do
   eval export ${envname[$i]}=${envvalue[$i]}
done

# Establish software binanry

if [ ! -f $TOMCAT_SOFTWARE ]; then 
   statsmessage "Tomcat software $TOMCAT_SOFTWARE check" "fail"
   exit 4
fi

# Check current Tomcat  target
# Display Current Tomcat setting

echo "Operation environment"
$root_dir/tomcat/bin/version.sh | tee /tmp/tomcat_version.log 
$root_dir/java/bin/java -cp $root_dir/tomcat/lib/catalina.jar org.apache.catalina.util.ServerInfo > /tmp/tomcatversion.txt 2>&1
data=( `cat /tmp/tomcatversion.txt | grep "Server number:" ` )
curr_version=${data[2]}
target_version=${TOMCAT_VERSION}


echo "Current Version: $curr_version"
echo "Target version: $target_version"

if [ "$curr_version" == "$atrget_version" ]; then
   echo "No upgrade is required - process skipped"
   if [ ${enforce} != "force" ]; then
      exit
   fi
fi 

#Stop existing tomcat instance 
for jvm in $root_dir/tomcatprofile/*
do
    echo "Stopping $jvm instance"
    su - wasadmin -c "${jvm}/bin/shutdown.sh"
    if [ $? -eq 0 ]; then
       echo "$JVM instance stopped"
    fi
       
done

#Upgrade tomcat
#Install tomcat software 
TomcatRefresh="true"

TOMCAT_HOME=/app/bin/apache
if [ -L $root_dir/tomcat ]; then
   #Check tomcat version
   $root_dir/java/bin/java -cp $root_dir/tomcat/lib/catalina.jar org.apache.catalina.util.ServerInfo > /tmp/tomcatversion.txt 2>&1
   data=( `cat /tmp/tomcatversion.txt | grep "Server number:" ` )
   currversion=${data[2]}

   echo "Tomcat current version: ${currversion}"
   echo "Tomcat target version:  ${TOMCAT_VERSION}"
   if [[ "${currversion}" < "${TOMCAT_VERSION}" ]]; then
      TomcatRefresh="true"
   else
      TomcatRefresh="false"
      statsmessage "Tomcat already installed on $TOMCAT_SOFTWARE, skip the Tomcat installation step" "ok"
   fi
fi
if [ ${TomcatRefresh} = "true" ]; then
   mkdir -p ${TOMCAT_HOME}
   tar -xzf ${TOMCAT_SOFTWARE} -C ${TOMCAT_HOME}
   if [ $? -ne 0 ]; then
      statsmessage "TOMCAT installed at $TOMCAT_HOME" "fail"
      exit 8
   fi

   tomcat_ver=`tar -tvzf $TOMCAT_SOFTWARE | head -1| awk '{ print $6 }' `
   CATALINA_HOME=${TOMCAT_HOME}/${tomcat_ver%%/*}
   if [ -L $root_dir/tomcat ]; then
      rm $root_dir/tomcat
   fi
   ln -s $CATALINA_HOME $root_dir/tomcat
   if [ -L /app/bin/tomcat ]; then
      rm /app/bin/tomcat
   fi
   ln -s $CATALINA_HOME /app/bin/tomcat
   chown -R wasadmin:mqm ${TOMCAT_HOME}
   chmodpath o+rx ${TOMCAT_HOME}
fi

#Install Tomcat APR if needed
if [ ${TOMCAT_APR} == "true" ]; then
   aprctr=`rpm -qa | grep -c libapr1-devel`
   if [ ${aprctr} -lt 1 ]; then
      zypper -n in libapr1-devel
   fi
   opensslctr=`rpm -qa | grep -c libopenssl-devel`
   if [ ${opensslctr} -lt 1 ]; then
      zypper -n in libopenssl-devel
   fi
      if [ -z ${CATALINA_HOME} ]; then
      CATALINA_HOME=$root_dir/tomcat
   fi
   cp ${CATALINA_HOME}/bin/tomcat-native.tar.gz /tmp
   cd /tmp
   tar xvf tomcat-native.tar.gz
   cd /tmp/tomcat-native-*/jni/native
   ./configure --with-apr=/usr/bin/apr-1-config --with-ssl=yes --with-java-home=$root_dir/java --prefix=${CATALINA_HOME}
   if [ $? -ne 0 ]; then
      statsmessage "Tomcat APR installation" "fail"
      exit 8
   fi
   make
   make install

   chown -R wasadmin:mqm ${CATALINA_HOME}/lib

   statsmessage "Tomcat APR installation" "ok"

fi
  
statsmessage "Tomcat installation step" "ok"

#Populate tomcat specific jar to ANT
cp $root_dir/tomcat/lib/catalina-ant.jar $root_dir/ant/lib/
cp $root_dir/tomcat/lib/tomcat-coyote.jar $root_dir/ant/lib/
cp $root_dir/tomcat/lib/tomcat-util.jar $root_dir/ant/lib/
cp $root_dir/tomcat/bin/tomcat-juli.jar $root_dir/ant/lib/

statsmessage "Copy Tomcat artifact to ANT" "ok"

#Start existing tomcat instance 
for jvm in $root_dir/tomcatprofile/*
do
    echo "Startting $jvm instance"
    su - wasadmin -c "${jvm}/bin/startup.sh"
done


#done
statsmessage "Overall Tomcat installation" "ok"
exit 0
