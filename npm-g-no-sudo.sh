#!/bin/sh

usage()
{
cat << EOF
usage: $0 [-d]

This script is intended to fix the common problem where npm users
are required to use sudo to install global packages.

It will backup a list of your installed packages remove all but npm,
then create a local directory, configure node to use this for global installs
whilst also fixing permissions on the .npm dir before, reinstalling the old packages.

OPTIONS:
   -h	Show this message
   -d	debug
EOF
}


DEBUG=0
while getopts "dv" OPTION
do
     case $OPTION in
         d)
             DEBUG=1
             ;;
         ?)
             usage
             exit
             ;;
     esac
done

to_reinstall='/tmp/npm-reinstall.txt'

printf "\nSaving list of existing global npm packages\n"
npm -g list --depth=0

#Get a list of global packages (not deps)
#except for the npm package
#save in a temporary file.
npm -g list --depth=0 --parseable --long | cut -d: -f2 | grep -v '^npm@\|^$' > $to_reinstall

printf "\nRemoving existing packages temporarily - you might need your sudo password\n\n"

#List the file
#replace the version numbers
#remove the newlines
#and pass to npm uninstall
uninstall='sudo npm -g uninstall'
if [ 1 = $DEBUG ]; then
	printf "Debug mode: won't run uninstall\n\n"

	uninstall='echo'
fi
if [ -s $to_reinstall ]; then
	cat $to_reinstall | sed -e 's/@.*//' | xargs $uninstall
fi

#roll back changes if uninstall fails
if [ $? -ne 0 ]; then
    printf "\nSome npm packages could not in be uninstalled. Attempting to roll back changes.\n\n"

    cat $to_reinstall | xargs sudo npm -g install
    rm $to_reinstall

    exit 1
fi

oldnpmdir="/usr/local/lib/node_modules"
npmdir="$HOME/.npm-packages"

printf "\nMake a new directory $npmdir for our "-g" packages\n"

if [ 0 = $DEBUG ]; then
	mkdir -p $npmdir
	npm config set prefix $npmdir
fi

printf "\nFix permissions on the .npm directories\n"

me=`whoami`
sudo chown -R $me ~/.npm

printf "\nReinstall packages\n\n"

#list the packages to install
#and pass to npm
install='npm -g install'
if [ 1 = $DEBUG ]; then
    printf "Debug mode: won't run install\n\n"

	install='echo'
fi
if [ -s $to_reinstall ]; then
	cat $to_reinstall | xargs $install
fi

#roll back changes if reinstall fails
if [ $? -ne 0 ]; then
    printf "\nSome npm packages could not in be re-installed. Attempting to roll back changes.\n\n"

    npm config set prefix $oldnpmdir
    cat $to_reinstall | xargs sudo $install
    rm $to_reinstall

    exit 1
fi

envfix='
NPM_PACKAGES="%s"
NODE_PATH="$NPM_PACKAGES/lib/node_modules:$NODE_PATH"
PATH="$NPM_PACKAGES/bin:$PATH"
# Unset manpath so we can inherit from /etc/manpath via the `manpath`
# command
unset MANPATH  # delete if you already modified MANPATH elsewhere in your config
MANPATH="$NPM_PACKAGES/share/man:$(manpath)"
'

printf "\nUpdate .bashrc with the paths and manpaths\n\n"

#create .bashrc if need be, then add path info
if [ ! -e ~/.bashrc ] || ! grep -q 'NPM_PACKAGES="%s"' ~/.bashrc; then
    printf "$envfix" $npmdir >> ~/.bashrc
fi

#make sure .bashrc is getting sourced in bash_profile
if ! grep -q 'source ~/.bashrc' ~/.bash_profile; then
    echo 'source ~/.bashrc' >> ~/.bash_profile
fi

source ~/.bash_profile

rm $to_reinstall

printf "\nDone - current package list:\n\n"
npm -g list -depth=0
