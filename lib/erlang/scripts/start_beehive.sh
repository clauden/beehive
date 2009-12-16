#!/bin/sh

progdir=$(dirname $0)
progname=$(basename $0)
grep=$(which grep)
version="0.1"

if [ ! -f ebin/beehive-*.boot ]; then
	make && make boot
fi

print_usage() {
cat <<EOF

Usage: $progname options

Start beehive. This will start the different types of servers for the different layers of beehive. Pass the type of the server 
to start with the '-t' flag. If the server is going to join an existing beehive, make sure you pass the node name of the beehive
server with the '-s' flag.

OPTIONS
	-m                                  Mnesia directory (defaults to ./db)
	-c, --config_file                   Config file
	-n                                  Name of the erlang process (useful for multiple nodes on the same instance)
	-r, --routing_parameter             Route on the routing parameter (defaults to 'Host')
	-e, --erlang_opts                   Additional erlang options
	-c, --user_defined_event_handler    Module name of the callback module
	-q, --bee_picker                    Name of the method that contains the bee chooser
	-s, --seed                          Pass in the seed node
	-l, --log_path                      Path of the logs
	-p, --client_port                   Port to run the router
	-i, --initial_bees                  Initial bees to start the bee_srv
	-t, --type                          Type of node to start (default: router)
	-g, --bee_strategy                  Strategy to choose a bee. (default: random)
	-z, --git_repos_path                Git repos path
	-d                                  Daemonize the process
	-v                                  Verbose
	-h, --help                          Show this screen
	
EOF
}

print_version() {
cat <<EOF
$progname $version

Copyright (C) 2009 Ari Lerner
EOF
}

# Defaults
HOSTNAME=`hostname -f`
MNESIA_DIR="/opt/beehive/db"
DAEMONIZE_ARGS=""

BEEHIVE_OPTS="-beehive"
ROUTER_OPTS="-router"
NODE_OPTS="-node"
STORAGE_OPTS="-storage"

TYPE="router"
REST="true"
VERBOSE=false
STRATEGY="random"
RELOADER_OPTS="-s reloader"
ERL_OPTS="-pa $PWD/ebin -pa $PWD/include -pz $PWD/deps/*/ebin"

SHORTOPTS="hm:n:dp:t:g:r:s:vi:e:b:q:l:z:c:"
LONGOPTS="help,version,client_port,type,bee_strategy,routing_parameter,seed,mnesia_dir,daemonize"
LONGOPTS="$LONGOPTS,initial_bees,erlang_opts,user_defined_event_handler,bee_picker,log_path,git_repos_path,config"

if $(getopt -T >/dev/null 2>&1) ; [ $? = 4 ] ; then # New longopts getopt.
	OPTS=$(getopt -o "$SHORTOPTS" --longoptions "$LONGOPTS" -n "$progname" -- "$@")
else # Old classic getopt.
  # Special handling for --help and --version on old getopt.
	case $1 in --help) print_usage ; exit 0 ;; esac
	case $1 in --version) print_version ; exit 0 ;; esac
	OPTS=$(getopt $SHORTOPTS "$@")
fi

if [ $? -ne 0 ]; then
	echo "'$progname --help' for more information" 1>&2
	exit 1
fi

# eval set -- "$OPTS"
while [ $# -gt 0 ]; do
   : debug: $1
   case "$1" in
		--help)
			usage
			exit 0
			;;
		-n|--name)
			NAME=$2
			shift 2;;
		-m|--mnesia_dir)
			MNESIA_DIR=$2
			shift 2;;
		-l|--log_path)
			LOG_PATH=$2
			BEEHIVE_OPTS="$BEEHIVE_OPTS log_path '$2'"
			shift 2;;
		-r|--routing_parameter)
			ROUTER_OPTS="$ROUTER_OPTS routing_parameter '$2'"
			shift 2;;
		-p|--client_port)
			ROUTER_OPTS="$ROUTER_OPTS client_port $2"
			shift 2;;
		-s|--seed)
			if [ $(echo $2 | $grep '@') ]; then
				SEED=$2
			else
				SEED="$2@$HOSTNAME"
			fi
			shift 2;;
		-q|--bee_picker)
			ROUTER_OPTS="$ROUTER_OPTS bee_picker '$2'"
			shift 2;;
		-c|--config_file)
			CONFIG_FILE=$2
			BEEHIVE_OPTS="$BEEHIVE_OPTS config_file '$CONFIG_FILE'"
			shift 2;;
		-e|--erlang_opts)
			echo "Erlang opts: $*"
			ERL_OPTS="$ERL_OPTS $2"
			shift 2;;
		-b|--user_defined_event_handler)
			ROUTER_OPTS="$BEEHIVE_OPTS user_defined_event_handler $2"
			shift 2;;
		-i|--initial_bees)
			ROUTER_OPTS="$ROUTER_OPTS bees '$2'"
			shift 2;;
		-t|--type)
			TYPE=$2
			shift 2;;
    -g|--bee_strategy)
			ROUTER_OPTS="$ROUTER_OPTS bee_strategy '$2'"
      shift 2;;
		-d|--daemonize)
			DAEMONIZE_ARGS="-detached -heart"
			RELOADER_OPTS=""
			shift;;
		-z|--git_repos_path)
			STORAGE_OPTS="$STORAGE_OPTS git_repos_path '$2'"
			shift 2;;
		-v)
			VERBOSE=true
			shift;;
		--)
			shift
			break;;
		*)
			print_usage; exit 0
			;;
	esac
done

# Sanity checks
if [ -z $NAME ]; then
	NAME="$TYPE@$HOSTNAME"
fi

if [ $TYPE != 'router' ]; then
	ROUTER_OPTS="$ROUTER_OPTS run_rest_server false"
fi

if [ ! -d $MNESIA_DIR ]; then
	echo "
--- There was an error ---
The database directory $MNESIA_DIR does not exist
Either make the directory manually or specify a different one in a
config file or at the command-line with the '-m' swtich.
Exiting...
	"
	exit 2
fi

# Set config file options
# This means a config file has been set, so let's find out more file fun
if [ ! -z $CONFIG_FILE ]; then	
	# Set some erlang options, if they are in the config file
	MORE_ERL_OPTS=$(erl -pa ./ebin -run beehive_control get_config_option "$CONFIG_FILE" erlang_opts -s init stop -noshell)
	if [ ! -z "$MORE_ERL_OPTS" ]; then
		ERL_OPTS="$ERL_OPTS $MORE_ERL_OPTS"
	fi
	
	MORE_TYPE=$(erl -pa ./ebin -run beehive_control get_config_option "$CONFIG_FILE" type -s init stop -noshell)
	if [ ! -z "$MORE_TYPE" ]; then
		TYPE="$MORE_TYPE"
	fi
	
	# UGLY. maybe fix this up with something better?
	# We do this so that our config file can define things that we need at the start up time
	ANAME=$(erl -pa ./ebin -run beehive_control get_config_option "$CONFIG_FILE" name -s init stop -noshell)
	if [ ! -z "$ANAME" ]; then
		NAME=$ANAME
	fi
	
	AMNESIA_DIR=$(erl -pa ./ebin -run beehive_control get_config_option "$CONFIG_FILE" mnesia_dir -s init stop -noshell)
	if [ ! -z "$AMNESIA_DIR" ]; then
		MNESIA_DIR=$AMNESIA_DIR
	fi
	
	ASEED=$(erl -pa ./ebin -run beehive_control get_config_option "$CONFIG_FILE" seed -s init stop -noshell)
	if [ ! -z "$ASEED" ]; then
		if [ $(echo $ASEED | $grep '@') ]; then
			SEED=$ASEED
		else
			SEED="$ASEED@$HOSTNAME"
		fi
		
		BEEHIVE_OPTS="$BEEHIVE_OPTS seed '$SEED' "
	fi
	
fi

BEEHIVE_OPTS="$BEEHIVE_OPTS node_type $TYPE "

if [ $TYPE == 'router' ]; then
	APP_OPTS=$ROUTER_OPTS
elif [ $TYPE == 'node' ]; then
	APP_OPTS=$NODE_OPTS
elif [ $TYPE == 'storage' ]; then
	APP_OPTS=$STORAGE_OPTS
fi

if $VERBOSE; then
cat <<EOF
	Running with:
    Erlang opts:     $ERL_OPTS
    Mnesia dir:      '$MNESIA_DIR'
    Name: 		       '$NAME'
    Beehive opts:    $BEEHIVE_OPTS
    App opts:        $APP_OPTS
EOF
fi

erl $ERL_OPTS \
    $RELOADER_OPTS \
		-mnesia dir \'$MNESIA_DIR\' \
		-name $NAME \
		$BEEHIVE_OPTS \
		$APP_OPTS \
		$DAEMONIZE_ARGS \
    -boot beehive-$version
