#!/bin/bash
#Varables 
envidx=0
inptfile=$1
root_dir=$2
enforce=${3:-noforce}

# Validation section
if [ $# -lt 1 ]; then
   echo "Usage: tomcat_wilyupgrade.sh <inputfile> "
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
          *)        echo "unknown instance variable ${recordtype[2]} - process abort"
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

# Set UMASK to 022
umask 022

#House keeping 
echo "Start JDK for tomcat upgrade process at "`date +"%F %T"`

#Remove JDK
#To prevent other porocess depends on this JDK, remove symlink only  
if [ -L $root_dir/java ]; then
   rm $root_dir/java
   if [ $? -eq 0 ]; then
      statsmessage "Remove JDK symlink" "ok"
   else
      statsmessage "Remove JDK symlink" "fail"
      exit 4
   fi
fi

#Install JDK 
JAVA_PROVIDER=`echo $JAVA_PROVIDER | tr ":lower:" ":upper:" `
if [ -z $JAVA_PROVIDER ]; then
   JAVA_PROVIDER="IBM"
fi

if [ $JAVA_PROVIDER == "SUN" ]; then
   if [ ! -d $JAVA_HOME ]; then
      if [ ! -f $JAVA_SOFTWARE ]; then
         statsmessage "JDK install at $JAVA_SOFTWARE" "fail"
         echo "==>JDK binary does not exist; Process abort"
         exit 4
      fi
      #Silent install Sun JDK then move to final location
      rm -r /tmp/sun 2>/dev/null
      mkdir /tmp/sun; cd /tmp/sun
      installsuffix=${JAVA_SOFTWARE##*.}
      if [ $installsuffix == "bin" ]; then
          # sunjdk 6 with bin as suffix
         echo "yes" | eval "$JAVA_SOFTWARE > /tmp/java_install.log"
         if [ $? -ne 0 ]; then
            statsmessage "JDK install at $JAVA_SOFTWARE" "fail"
            echo "==>JDK binary install failed, please check /tmp/java_install.log; Process abort"
            exit 4
         fi
      else
         # sun jdk 7 with tar.gz as suufix
         tar -xzf $JAVA_SOFTWARE
      fi

      jdkversion=`ls /tmp/sun/`
      if [ "${JAVA_HOME}" != "/app/bin/sun/${jdkversion}/jre" ]; then
         statsmessage "JDK install at $JAVA_SOFTWARE" "fail"
         echo "==> installation target /opt/sun/${jdkversion}/jre mismatch configure target ${JAVA_HOME} ; Process abort"
         exit 4
      fi
      mkdir -p /app/bin/sun
      mv /tmp/sun/${jdkversion} /app/bin/sun/
   else
      statsmessage "JDK already installed on $JAVA_SOFTWARE, skip the JDK installation step" "warn"
   fi
else
   #IBM JDK
   if [ ! -f $JAVA_SOFTWARE ]; then
      statsmessage "JDK install at $JAVA_SOFTWARE" "fail"
      echo "==>JDK binary does not exist; Process abort"
      exit 4
   fi

   installsuffix=${JAVA_SOFTWARE##*.}
   if [ ${installsuffix} == "tgz" ]; then
      #The java path may already included in tgz file
      actualpath=`tar -tzf ${JAVA_SOFTWARE} | head -1`
      actualpath=/${actualpath%?} 

      if [ `echo ${actualpath} | grep -c "/app/bin/ibm/" ` -eq 0 ]; then 
         echo "${actualpath} contains incorrect format, process abort"
         exit 8
      fi   

      if [ "${actualpath}/jre" != "${JAVA_HOME}" ]; then
         echo "WARNING: JAVA_HOME changed from ${JAVA_HOME} to ${actualpath}/jre"
         JAVA_HOME=${actualpath}/jre
      fi 

   fi

   if [ -d $JAVA_HOME ]; then
      installjdkdir=${JAVA_HOME%/*}
      if [ -d ${installjdkdir}-bkup ]; then
         rm -r $installjdkdir}-bkup
      fi 
      mv $installjdkdir ${installjdkdir}-bkup
   fi

   mkdir -p $JAVA_HOME
   if [ ${installsuffix} == "tgz" ]; then
      tar -xzf $JAVA_SOFTWARE -C /
   else 
      tar -xf $JAVA_SOFTWARE -C $JAVA_HOME
   fi

   if [ $? -ne 0 ]; then
      statsmessage "JDK install at $JAVA_SOFTWARE" "fail"
      echo "==>failed to untar $JAVA_SOFTWARE, process abort"
      exit 8
   fi
fi

#Install JDK Common Section
if [ -L $root_dir/java ]; then
   rm $root_dir/java
fi

ln -s ${JAVA_HOME} $root_dir/java
chown -R wasadmin:mqm ${JAVA_HOME}
chmodpath o+rx ${JAVA_HOME}
statsmessage "JDK install to $JAVA_HOME" "ok"

#done
echo "Upgrade completed at " `date +"%F %T"`
exit 0
