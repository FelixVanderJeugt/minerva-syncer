#!/bin/bash

#Minerva syncer
#Original script by Felix Van Der Jeugt
#Makeover by Pieter Vander Vennet

# Some constants.
temp1="/tmp/temp1"
temp2="/tmp/temp2"
temptree="/tmp/temptree"
home="https://minerva.ugent.be/"
configdir="$XDG_CONFIG_HOME/minerva-syncer"
destdir="~/Minerva"
interactive=0 #asks per file to download. Is promted on each run
override=1 # always overrides local changes if 1, and if not interactive

blacklist=""
build_blacklist=0 # builds the blacklist if one

# Checks whether space separated $1 contains $2.
contains() {
    for member in $1; do
        if [ "$member" == "$2" ]; then
            return 0
        fi
    done
    return 1
}

# The cookie files. We need two, as curl wants an in and an out cookie.
# I alias the curl method to include a method which swaps the two
# files.
cin="/tmp/cookie1"
cout="/tmp/cookie2"
swap_cookies() {
    ctemp="$cin"
    cin="$cout"
    cout="$ctemp"
}

#asks a question
#the answer will be stored in answer
#$2 will be the options
#$3 the question
ask_question() {
	read -p "$1 [$2]: " $3
	while ! contains "$2" "${answer:0:1}"; do
        read -p "Please reply with any of [$1]. " $3
    done
}

ask_and_blacklist(){
	ask_question  "Sync or Blacklist $1?" "s b" answer
	if  [ "$answer" == "b" ] ; then
		blacklist="$blacklist $1;"
	fi
}

ask_override(){
	if [ $interactive -eq 1 ] ; then
		ask_question "Override $1?" "y n" answer
		if [ "$answer" == "y" ] ; then
			return 1
		else
			return 0
		fi
	else
		return $override
	fi
}


# Methods to escape file names:
# - Replace slashes and spaces from file names, so they can be used in
#   the urls.
# - Escape slashes to use filenames in sed substitutions.
url_escape() {
    echo "$1" | sed -e 's_/_%2F_g' -e 's/ /%20/g'
}
sed_escape() {
    echo "$1" | sed -e 's_/_\\/_g'
}

ask_new_or_keep() {
	__value=${!2}
	if [ ! "$__value" == "" ] ; then
 	 		echo "Current $1:"
 		echo "	${!2}"
	    read -p "Enter new $1, or press enter to keep \"${!2}\": " answer
 	else
 		echo
 		read -p "Enter $1: " answer
 	fi 
    
    echo
    if [ ! "$answer" == "" ] ; then
    	eval "$1=\"$answer\""	
    fi
}

initial_config() {
	# Ask the user some questions.
    echo
    echo "Welcome to minerva-syncer."
    echo
    echo "It seems this is the first time you're running the script,"
    echo "or that you want to change the settings."
    echo "Before we start synchronizing with Minerva, I'll need to know"
    echo "you're UGent username."
    ask_new_or_keep "username" username
 	
    echo
    echo "Pleased to meet you, $username."
    echo
    echo "If you want, I could remember your password, so that you do"
    echo "not have to enter it every time. However, since I have to"
    echo "pass it to Minerva, I'll have to save it in plain text."
    echo "Hit enter if you don't want your password saved."
    echo
    stty -echo
    read -p "UGent password: " password; echo
    stty echo
    echo
    echo "Now, which folder would you like so synchronize Minerva to?"
   	echo "Enter the absolute path"
    echo
    
	ask_new_or_keep "destination" destdir
 	    
	ask_question "Do you want to sync all courses? y for full download" "y n" answer
	if [ "$answer" == "n" ] ; then
		echo "We will ask you later what courses you want to download"
		build_blacklist=1
	fi
	
	echo
	echo "Override local changes:"
	echo
	echo "When files are changed on minerva and the local filesystem,"
	ask_question "would you like the local changes to be overwritten?" "y n" answer
	if [ "$answer" == "y" ] ; then
		override=1
	else
		override=0
	fi

    echo
    echo "OK, that's it. Let's get synchronizing."
    echo "Your settings will be saved to $configdir/config"
    
     # Create the target directory if it does not yet exist.
    if test ! -d "$destdir"; then
        mkdir "$destdir"
    fi
    datafile="$destdir/.mdata"
    date > "$datafile"
    
     # Create the config directory.
    if test ! -d "$configdir/"; then
        mkdir "$configdir/"
        echo "Configdir did not exist yet. We created it for you"
    fi

    { # Let's write a new config file.
        echo "username=\"$username\""
        echo "password=\"$password\""
        echo "destdir=\"$destdir\""
        echo "override=\"$override\""
        #interactive is not saved, as it's queried each time!
    } > "$configdir/config"
}

load_or_ask_settings() {
	# First, loading the config file.
	if test -e "$configdir/config"; then
    	# Yes, this is not secure. Don't edit the file, then.
    	echo "Loading settings from $configdir/config"
    	. "$configdir/config"
    	echo "Syncing to $destdir"
	else
	   initial_config
	fi

	
	ask_question "Do you want to change the profile settings?" "y n" answer
	if [ "$answer" == "y" ] ; then
		initial_config
	fi
	
	#ask_question "Do you want to run in interactive mode?" "y n" answer
	#if [ "$answer" == "y" ] ; then
	#	interactive=1
	#fi
	
	

	if test -z "$password"; then
	    stty -echo
	    read -p "Password for $username: " password; echo
	    stty echo
	fi
}

blacklisted() {
	lst=`echo $blacklist | sed "s/; /\n/g" | sed "s/;$//"`
	for item in $blacklist
	do
		if [ "$item" == "$1;" ]; then
			return 1
		fi
	done
	return 0
}

build_file_tree(){
	# Initializing cookies and retrieving authentication salt.
	echo -n "Initializing cookies and retrieving salt... "
	curl -c "$cout" "https://minerva.ugent.be/secure/index.php?external=true" --output "$temp1" 2> /dev/null
	swap_cookies

	salt=$(cat "$temp1" | sed '/authentication_salt/!d' | sed 's/.*value="\([^"]*\)".*/\1/')
	echo "done."

	# Logging in.
	echo -n "Logging in as $username... "
	curl -b "$cin" -c "$cout" \
		--data "login=$username" \
		--data "password=$password" \
		--data "authentication_salt=$salt" \
		--data "submitAuth=Log in" \
		--location \
		--output "$temp2" \
		    "https://minerva.ugent.be/secure/index.php?external=true" 2> /dev/null
	swap_cookies
	echo "done."

	# Retrieving header page to parse.
	echo -n "Retrieving minerva home page... "
	curl -b "$cin" -c "$cout" "http://minerva.ugent.be/index.php" --output "$temp1" 2> /dev/null
	echo "done."

	echo "Constructing Minerva Document tree..."
	# Parsing $temp1 and retrieving minerva document tree.
	cat "$temp1" | sed '/course_home.php?cidReq=/!d' | # filter lines with a course link on it.
		sed 's/.*course_home\.php?cidReq=\([^"]*\)">\([^<]*\)<.*/\2,\1/' | # separate course name and cidReq with a comma.
		sed 's/ /_/g' | # avoid trouble by substituting spaces by underscores.
		cat - > "$temp2"

	# Make a hidden file system for the synchronizing.
	mkdir -p "$destdir/.minerva"

	for course in $(cat "$temp2"); do
		name=$(echo "$course" | sed 's/,.*//')
		cidReq=$(echo "$course" | sed 's/.*,//')
		link="http://minerva.ugent.be/main/document/document.php?cidReq=$cidReq"
		if [ $build_blacklist -eq 1 ] ; then
			ask_and_blacklist $name
		fi

		blacklisted $name
		if [ $? -eq 1 ] ; then
			echo "Skipping $name (blacklisted)"
		else
			echo "Building tree for $name"
		
			# Make a directory for the course.
			mkdir -p "$destdir/.minerva/$name"

			# Retrieving the course documents home.
			curl -b "$cin" -c "$cout" "$link" --output "$temp1" 2> /dev/null
			swap_cookies

			# Parsing the directory structure from the selector.
			folders=$(cat "$temp1" |
				sed '1,/Huidige folder/d' | # Remove everything before the options.
				sed '/_qf__selector/,$d' |  # Remove everything past the options.
				sed '/option/!d' | # Assure only options are left.
				sed 's/.*value="\([^"]*\)".*/\1/' # Filter the directory names.
			)

			# For each directory.
			for folder in $folders; do
				# Make the folder in the hidden files system.
				localdir="$destdir/.minerva/$name/$folder"
				mkdir -p "$localdir"

				# Retrieving directory.
				curl -b "$cin" -c "$cout" "$link&curdirpath=$(url_escape $folder)" --output "$temp1" 2> /dev/null
				swap_cookies

				# Parsing files from the directory.
				files=$(cat "$temp1" |
				    # Only lines with a file or a date in. (First match: course site; second match: info site, third: date)
				    sed -n -e '/minerva\.ugent\.be\/courses....\/'"$cidReq"'\/document\//p' \
				           -e '/minerva\.ugent\.be\/courses_ext\/'"${cidReq%_*}"'ext\/document\//p' \
				           -e '/[0-9][0-9]\.[0-9][0-9]\.[0-9][0-9][0-9][0-9] [0-9][0-9]:[0-9][0-9]/p' |
				    # Extract file url.
				    sed 's|.*href="\([^"]*/document'"$folder"'[^"]*?cidReq='"$cidReq"'\)".*|\1|' | 
				    # Extract the date.
				    sed 's/.*\([0-9][0-9]\)\.\([0-9][0-9]\)\.\([0-9][0-9][0-9][0-9]\) \([0-9][0-9]\):\([0-9][0-9]\).*/\2\/\1_#_\4:\5_#_\3/' |
				    # Join each url with the file name and date.
				    sed -n '/http:/{N;s/\n/,/p;}' | sed 's/\(.*\)\/\([^\/]*\)?\(.*\)/&,\2/'
				)
				for file in $files; do
				    filename=${file#*,*,}
				    rest=${file%,*}
				    echo "$rest" | sed -e 's/,/\n/' -e 's/_#_/ /g' > "$localdir/$filename.new"
				done
			done
		fi # end of building tree. This fi is to test blacklistness
	done
	echo " done building the tree!"

	if [ $build_blacklist -eq 1 ] ; then
		ask_question "Save the blacklist to your config file?" "y n" answer
		if [ "$answer" = "y" ] ; then
			echo "blacklist=\"$blacklist\"" >> "$configdir/config"
		fi
	fi
}

sync_files() {
	# Filtering the list of files to check which are to be updated.
	echo "Downloading individual files... "
	# Retrieve the last update time.
	last=$(date +"%s" -d "$(head -1 "$datafile")")
	for file in $(find "$destdir/.minerva/"); do

		localfile=${file/.minerva\//}
		localfile=${localfile%.new}
		name=${file#*.minerva/}
		name=${name/.new/}

		# Do not take any files matching in datafile.
		if grep "$name" "$datafile" > /dev/null 2>&1; then
		    continue
		fi

		# Can't download directories, yes?
		if [ "${file:(-4)}" != ".new" ]; then
		    mkdir -p "$localfile"
		    continue
		fi

		theirs=$(date +"%s" -d "$(cat "$file" | tail -1)")
		answer="n"
		if [ -e "$localfile" ]; then # We have once downloaded the file.
		    ours=$(stat -c %Y "$localfile")
		    if (( ours > last && theirs > last )); then # Locally modified.
		    	if [ $interactive -eq 1]; then
					ask_question "$name was updated both local and online. Overwrite?" "y n" answer
				else
					if [ $override -eq 0 ]; then
						answer="n"
					else
						answer="y"
					fi
		    	fi
		    fi
		else
		 	if [ $interactive -eq 1 ]; then
		    	ask_question "$name was created online. Download?" "y n" answer
		    else
		    	answer="y"
		    fi
		fi

		if [ "$answer" == "y" ] || [ "$answer" == "" ]; then # Download.
			echo "Downloading $file"
		    curl -b "$cin" -c "$cout" --output "$temp1" "$(head -1 "$file")"
		    swap_cookies
		    mv "$temp1" "$localfile"
		else 
			echo "Not downloading $file"
		fi
	done
}

# Let's start our main program.
load_or_ask_settings
build_file_tree
sync_files

#mv "$datafile" "$temp1"
#cat "$temp1" | sed "1c $(date)" > "$datafile"
#echo "Done. Your local folder is now synced with Minerva."
