#!/bin/bash
#
# SVN shell : improved bash with svn information
#
# Original: Alex Gavrishev <alex.gavrishev@gmail.com>
# Updated: Gady Barak <gadybarak@gmail.com>

_update_prompt () {
    ## Save $? early, we'll need it later
    local exit="$?"

    ## define some colors
    local BLACK="\[\033[0;30m\]"
    local BLACKBOLD="\[\033[1;30m\]"
    local RED="\[\033[0;31m\]"
    local REDBOLD="\[\033[1;31m\]"
    local GREEN="\[\033[0;32m\]"
    local GREENBOLD="\[\033[1;32m\]"
    local YELLOW="\[\033[0;33m\]"
    local YELLOWBOLD="\[\033[1;33m\]"
    local BLUE="\[\033[0;34m\]"
    local BLUEBOLD="\[\033[1;34m\]"
    local PURPLE="\[\033[0;35m\]"
    local PURPLEBOLD="\[\033[1;35m\]"
    local CYAN="\[\033[0;36m\]"
    local CYANBOLD="\[\033[1;36m\]"
    local WHITE="\[\033[0;37m\]"
    local WHITEBOLD="\[\033[1;37m\]"
    local RESETCOLOR="\[\e[00m\]"

    local arrow_up=`echo -e "\xe2\x86\x91"`
    local arrow_down=`echo -e "\xe2\x86\x93"`

    ## Initial prompt
    _prompt="\n$RED\u $PURPLE@ $GREEN\w $RESETCOLOR$GREENBOLD";

    ## Color git status if any
    branch=`svn info 2>/dev/null | grep "Relative URL"`
    if [ -n "$branch" ] ; then
		# strip beginning
		prefix='Relative URL: ^/'
		branch=${branch#$prefix}

		if  [ "$branch" != "$SVNSHELL_BRANCH_CURRENT" ] ;
		then
			export SVNSHELL_BRANCH_PREV=$SVNSHELL_BRANCH_CURRENT
			export SVNSHELL_BRANCH_CURRENT=$branch
		fi

		if  [[ $branch == branches* ]] ;
		then
		    branch=${branch#'branches/'}
		fi
		if  [[ $branch == tags* ]] ;
		then
		    branch=${branch#'tags/'}
		fi

		svn_version=`svnversion`
        branch_revision=$svn_version
		branch_status=`svn status -q | cut -c 1-7 | grep -ve '^---' | grep --color=never -o . | sort -u | tr -d " \n"`
		if [[ "$svn_version" =~ ([0-9:]+)([MSP]+)? ]] ;
		then
		    branch_revision=${BASH_REMATCH[1]}
		fi

        if [ "$branch_status" ] ; then
            status_formatted="$RESETCOLOR[$REDBOLD$branch_status$RESETCOLOR]"
            branch="$REDBOLD$branch $status_formatted $BLUE$branch_revision$RESETCOLOR "
        else
            branch="$GREEN$branch$BLUE $branch_revision "
        fi

	    full_prompt="$_prompt $branch"
	else
		export SVNSHELL_BRANCH_CURRENT=
		export SVNSHELL_BRANCH_PREV=
	    full_prompt="$_prompt "
    fi
    export PS1="$full_prompt $BLUE[\#] → $RESETCOLOR"

}

function _param_to_branch() {
	local branch=$1
    if [ -n "$branch" ] ; then
		branch=${branch%/}
		if [ "$branch" == "trunk" ]; then
			branch="trunk"
		elif [[ "$branch" == *\/* ]]; then
			branch=${branch#'^/'}
		else
			branch="branches/$branch"
		fi
	fi
	echo "$branch"
}

function _extract_branch_name() {
	local branch=$1
	if  [[ $branch == branches* ]] ;
	then
	    branch=${branch#'branches/'}
	fi
	if  [[ $branch == tags* ]] ;
	then
	    branch=${branch#'tags/'}
	fi
	echo "$branch"
}

function _switch() {
	local branch=$1
    if [ -n "$branch" ] ; then
		if [ "$branch" == "-" ]; then
			if  [ -n "$SVNSHELL_BRANCH_PREV" ] && [ "$SVNSHELL_BRANCH_CURRENT" != "$SVNSHELL_BRANCH_PREV" ];
			then
				svn switch ^/$SVNSHELL_BRANCH_PREV "${*:2}"
			fi
		else
			branch=$(_param_to_branch $branch)
			svn switch ^/"$branch" "${*:2}"
		fi
	else
		svn switch "$@"
	fi
}

function _branch() {
	local branch=$1
	local message=$2
    if [ -z "$branch" ] ; then
		svn ls ^/branches/ --verbose | sort
	else
		if [ -n "$message" ] ; then
			svn copy . ^/branches/"$branch" -m "$message"
		else
			svn copy . ^/branches/"$branch"
		fi
	fi
}

function _commit() {
	svn commit "$@"
	local RETVAL=$?
	[ $RETVAL -eq 0 ] && svn update
}

function _merge_branch() {
	local banch=$(_param_to_branch $1)
	if [ -z "$banch" ] ; then
		echo "mb <BranchName>"
	else
		svn merge ^/"$banch" "${*:2}"
		local RETVAL=$?
		[ $RETVAL -eq 0 ] && echo "Commit hint: ci -m \"Merge from $banch\""
	fi
}

function _reintegrate() {
	_merge_branch "$1" "--reintegrate"
}

function _mergelog() {
	local branch=$(_param_to_branch $1)
    if [ -z "$branch" ] ; then
		branch=$SVNSHELL_BRANCH_CURRENT
	fi
	local shortbranch=$(_extract_branch_name $branch)

	local message=
	local author=
	local rev=
	local date=
	local state=0

	svn log --limit 10 ^/$branch | while read line
	do
		if [[ "$line" == ---* ]]; then

			if [ "$state" -eq 3 ]; then
				echo "------------- $author [$date] -----------------------------------"
				echo "merge -c $rev ^/$branch ."
				echo "commit -m \"Merge from $shortbranch: $message\""
			fi

			state=1
		elif [ "$state" -eq 1 ]; then
			# r6733 | alex | 2014-07-07 16:09:21 +0300 (Mon, 07 Jul 2014) | 1 line
			state=2
			local OLD_IFS="$IFS"
			IFS=' | '
			local data=( $line )
			IFS="$OLD_IFS"

			rev=${data[0]#r}
			author=${data[1]}
			date="${data[2]} ${data[3]}"
			message=

		elif [ "$state" -eq 2 ]; then
			#empty line
			state=3
		elif [ "$state" -eq 3 ]; then
			#empty line
			if [ -n "$line" ]; then
			    message="$message $line"
			fi
		fi
	done
	# show last
	if [ "$state" -eq 3 ]; then
		echo "------------- $author [$date] -----------------------------------"
		echo "merge -c $rev ^/$branch ."
		echo 'commit -m "Merge from $shortbransh: $message"'
	fi
}

function _diff() {
	hash colordiff 2>/dev/null
	local RETVAL=$?
	if [ $RETVAL -eq 0 ]; then
		svn diff "$@" | colordiff
	else
		svn diff "$@"
	fi
}

function _intro() {
	echo "Welcome to SVNSHELL"
	_help
	echo ""
	hash colordiff 2>/dev/null || { echo "To display diff with colors install colordiff."; }
}

function _help() {
	echo "    Actions    : up | sw <BranchName> | sw - | ci -m \"<Message>\" | branch <BranchName> \"<Message>\" | mb <BranchName> | reintegrate | revert(all) |"
	echo "    Information: st | branch | di | log | mergelog"
}

function _exit() {
	export PROMPT_COMMAND=
	export PS1=$PS1_ORIGINAL
	unset SVNSHELL_BRANCH_CURRENT
	unset SVNSHELL_BRANCH_PREV
	unalias add
	unalias up
	unalias update
	unalias sw
	unalias switch
	unalias ci
	unalias commit
	unalias info
	unalias log
	unalias mergelog
	unalias status
	unalias st
	unalias stat
	unalias merge
	unalias branch
	unalias revert
	unalias revertall
	unalias di
	unalias mb
	unalias reintegrate
	unalias help
	unalias exit
}

PROMPT_COMMAND='_update_prompt'
export PROMPT_COMMAND
export PS1_ORIGINAL=$PS1
export SVNSHELL_BRANCH_CURRENT=
export SVNSHELL_BRANCH_PREV=

# Define shortcuts

alias add="svn add "
alias up="svn update "
alias update="svn update "
alias sw="_switch "
alias switch="svn switch "
alias ci="_commit "
alias commit="_commit "
alias info="svn info "
alias log="svn log --limit 10 "
alias mergelog="_mergelog "
alias status="svn status "
alias stat="svn status "
alias st="svn status "
alias merge="svn merge "
alias branch="_branch "
alias revert="svn revert "
alias revertall="svn revert --depth=infinity ."
alias di="_diff "
alias mb="_merge_branch "
alias reintegrate="_reintegrate "
alias help="_help "
alias exit="_exit "

_intro
