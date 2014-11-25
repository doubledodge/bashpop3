#!/bin/bash
# Script automates telnet POP3 mail management based on a script at 
# http://stackoverflow.com/questions/5911032/whats-the-best-method-for-retrieving-sender-subject-from-a-pop3-acct-via-the-c

STATE=1
USER=your@email.co.uk
echo "enter password for this POP3 email connecton"
read password
PASS=$password
HOST=your.pop3host.co.uk
PORT=pop3
declare -A MSGIDS
declare -i NUMID
NUMID=0 # counts the total number of emails on the server
declare -i CURID
CURID=0
declare -i NLINES
NLINES=100 # The total number of lines to list from the the body of the email
declare -i NMESSH
NMESSH=5  # The number of message headers to list at a time
declare -i STOP # final message of the headers to list
STOP=$NMESSH
declare -i MESID # holds the message number entered by the user
declare BODY # true when printing start of email body
declare BODYFOUND # made true after first blank line in email is found marking end of header
declare RELIST # true if the server emails need reslisting (ie on start or after deleting one)
RELIST=true
declare -i MAXLINE # number of lines to list before waiting for a key press
declare -i LINE # keep count of the number of lines listed
LINE=0
MAXLINE=20
# Launch telnet as a coprocess (N.B. coprocesses need a fairly recent version of bash/dash/sh 
coproc telnet $HOST $PORT

reqmsg()
{
  echo "TOP ${MSGIDS[$CURID]} 0" >&${COPROC[1]}
  ((CURID++))
}

listmail()
{
	((LINE++))
	if [ $LINE -ge $MAXLINE ] ; then 
		echo "$f"
		LINE=0
		echo "												enter return" 
		read entry
	else
		echo "$f"
	fi
}

askaction()
{
  echo "Enter action: list headers (f=first set, n=next set, p=previous set or s= same set, )"
  echo "   or enter a number to list the head or body of one email" 
  echo "   r restores any emails marked for deletion or q quits; deleteing them permanently!)"
  confused=true
  while $confused
	do
	read action
	case "$action" in
	f) CURID=0
		STOP=$(($CURID+$NMESSH))
		reqmsg
		STATE=7
	   	confused=false;;
	s) CURID=$(($CURID-$NMESSH))
		STOP=$CURID
		if [ $CURID -lt 0 ] ; then CURID=0 ; fi
		STOP=$(($CURID+$NMESSH))
		reqmsg
		STATE=7
	   	confused=false;;
	n)   if [ $(($CURID)) -ge $(($NUMID)) ]; then  CURID=$(($NUMID-$NMESSH)) ; fi
		STOP=$(($CURID+$NMESSH))
		reqmsg
		STATE=7
	   	confused=false;;
	p) CURID=$(($CURID-$NMESSH*2))
		if [ $CURID -lt 0 ] ; then CURID=0 ;fi
		STOP=$(($CURID-$NMESSH))
		if [ $STOP -le $NMESSH ] ; then STOP=$NMESSH ; fi
		reqmsg
		STATE=7
	   	confused=false;;
	r) echo "RSET" >&${COPROC[1]}; STATE=9
	   confused=false
	   echo "restoring any emails marked for deletion";;
	q) echo "QUIT" >&${COPROC[1]}; 
	   confused=false
	   echo "saying bye-bye" ; exit 0 ;;
    [0-9]*) MESID=$(($action))
		BODY=true
		STATE=6
		echo "TOP $MESID $NLINES" >&${COPROC[1]}
		BODYFOUND=false
		confused=false;;
	*) echo "response not understood, try again";;
	esac
    done
}

delorlist()
{
  echo "Delete this message (d) or display (h=header b=body) or return (u)"
  confused=true
#set -x
  while $confused
	do
	read action
	case "$action" in
	d) STATE=9
	   RELIST=true
	   echo "Mesage#  Size (bytes)"
	   echo "DELE $MESID" >&${COPROC[1]}
	   confused=false;;
	h) BODY=false
	   STATE=6
	   echo "TOP $MESID 0" >&${COPROC[1]}
	   BODYFOUND=false
	   confused=false;;
	b) BODY=true
	   STATE=6
	   echo "TOP $MESID $NLINES" >&${COPROC[1]}
	   BODYFOUND=false
	   confused=false;;
	u) askaction
	   confused=false;;
	*) echo "response not understood, try again";;
	esac
    done
}

headsorquit()
{
  echo "Enter action (l=re-list headers" 
  echo " r to restore any emails marked for deletion or q to quit)"
  confused=true
  while $confused
	do
	read action
	case "$action" in
	l) CURID=0; NUMID=0
		echo "LIST" >&${COPROC[1]}; STATE=4
	   confused=false;;
	r) echo "RSET" >&${COPROC[1]}; STATE=9
	   confused=false
		echo "last string read was ""$f"
#		set -x
	   echo "restoring any emails marked for deletion";;
	q) echo "QUIT" >&${COPROC[1]} ; STATE=5
	   confused=false
	   echo "saying bye-bye"; exit 0;;
	*) echo "response not understood, try again";;
	esac
    done
}

echo "initiating connection to $HOST , this may take up to a minute to respond"
while read -t 50 f <&${COPROC[0]}
 do
  case "$STATE" in
   1) case "$f" in
       +OK*) echo "USER $USER" >&${COPROC[1]}; echo "host responding, logging in now"; STATE=2;;
		*) echo "($f)";;
      esac;;
   2) case "$f" in
       +OK*) echo "PASS $PASS" >&${COPROC[1]}; STATE=3;;
	   # by default echoing to &2 directs to the console unless an error file is defined
       *) echo "Bad response to user command ($f)" >&2; exit 1;;
      esac;;
   3) case "$f" in
       +OK*) echo "LIST" >&${COPROC[1]}; STATE=4; echo "Mesage#  Size (bytes)";;
       *) echo "Bad response to password command ($f)" >&2; exit 1;;
      esac;;
   4) case "$f" in
       +OK*) STATE=5;;
       *) echo "Bad response to LIST command ($f)" >&2; exit 1;;
      esac;;
   5) case "$f" in # check the list command ran OK and collect the list for further processing
	   .)  if [ 0 -eq $NUMID ]; then 
			  echo "no messages on server"
			  headsorquit
			else 
			  RELSIST=false
			  echo "there are $NUMID messages on the server" 
			  askaction
			fi ;;
       [0-9]*) read msgid size < <(echo $f)
       		   echo "$msgid        $size"
               MSGIDS[$NUMID]=$msgid
               ((NUMID++));;
	  +OK*) echo "Server says OK ($f)" >&2; exit 1;;
       *) echo "Bad response to LIST command ($f)" >&2; exit 1;;
      esac;;
   6)   case "$f" in
		-ERR*) echo "$f" # assume this is not a valid message number
		      askaction;;
		"") 	BODYFOUND=true ;;
		.)	LINE=0
            delorlist;;
		*) if  $BODY   ; then
			if $BODYFOUND  ; then
			listmail
		   	  else
			    case "$f" in
			   	To:*) echo "$f";;
			   	From:*) echo "$f";;
			   	Subject:*) echo "$f";;
			    esac
 			 fi
		   else
			 listmail
		   fi;;
		esac;;
   7) case "$f" in
       +OK*) echo "message ${MSGIDS[$(($(($CURID))-1))]}"
			 STATE=8;; 
       *) echo "Bad response to TOP command ($f)" >&2; exit 1;;
      esac;;
   8) case "$f" in
	   .)   if [ $(($CURID)) -eq $(($STOP)) ]  || [ $(($CURID)) -eq $(($NUMID)) ]  
		    then askaction; else
			echo "CURID= $CURID NUMID= $NUMID "
			reqmsg; STATE=7
		    fi;; 
	   To:*) echo "$f";;
       From:*) echo "$f";;
       Subject:*) echo "$f";;
      esac;;
   9) case "$f" in
       +OK*) echo "LIST" >&${COPROC[1]} # need to rebuild the list after deleting one message
		 NUMID=0 
		 STATE=4 ;;
       *) echo "Bad response to DELE or RSET command ($f)" >&2; exit 1;;
      esac;;   
	*) echo "STATE $STATE and got $f";;
  esac
 done
