#!/bin/bash
#------------------------------------------------------------------------------
#
# Python for android
# https://github.com/tito/python-for-android
#
#------------------------------------------------------------------------------

# Modules
MODULES=$MODULES

# Paths
ROOT_PATH="$(dirname $(readlink -f $0))"
RECIPES_PATH="$ROOT_PATH/recipes"
BUILD_PATH="$ROOT_PATH/build"
LIBS_PATH="$ROOT_PATH/build/libs"
PACKAGES_PATH="$ROOT_PATH/.packages"
SRC_PATH="$ROOT_PATH/src"
JNI_PATH="$SRC_PATH/jni"
DIST_PATH="$ROOT_PATH/dist/default"

# Internals
CRED="\x1b[31;01m"
CBLUE="\x1b[34;01m"
CGRAY="\x1b[30;01m"
CRESET="\x1b[39;49;00m"
DO_CLEAN_BUILD=0

# Use ccache ?
which ccache &>/dev/null
if [ $? -eq 0 ]; then
	export CC="ccache gcc"
	export CXX="ccache g++"
fi

#set -x

function try () {
    "$@" || exit -1
}

function info() {
	echo -e "$CBLUE"$@"$CRESET";
}

function error() {
	echo -e "$CRED"$@"$CRESET";
}

function debug() {
	echo -e "$CGRAY"$@"$CRESET";
}

function get_directory() {
	case $1 in
		*.tar.gz)	directory=$(basename $1 .tar.gz) ;;
		*.tgz)		directory=$(basename $1 .tgz) ;;
		*.tar.bz2)	directory=$(basename $1 .tar.bz2) ;;
		*.tbz2)		directory=$(basename $1 .tbz2) ;;
		*.zip)		directory=$(basename $1 .zip) ;;
		*)
			error "Unknown file extension $1"
			exit -1
			;;
	esac
	echo $directory
}

function push_arm() {
	info "Entering in ARM enviromnent"

	# save for pop
	export OLD_PATH=$PATH
	export OLD_CFLAGS=$CFLAGS
	export OLD_CXXFLAGS=$CXXFLAGS
	export OLD_CC=$CC
	export OLD_CXX=$CXX
	export OLD_AR=$AR
	export OLD_RANLIB=$RANLIB
	export OLD_STRIP=$STRIP
	export OLD_MAKE=$MAKE

	# to override the default optimization, set OFLAG
	#export OFLAG="-Os"
	#export OFLAG="-O2"

	export CFLAGS="-mandroid $OFLAG -fomit-frame-pointer --sysroot $NDKPLATFORM"
	if [ $ARCH == "armeabi-v7a" ]; then
		CFLAGS+=" -march=armv7-a -mfloat-abi=softfp -mfpu=vfp -mthumb"
	fi
	export CXXFLAGS="$CFLAGS"

	# this must be something depending of the API level of Android
	export PATH="$ANDROIDNDK/toolchains/arm-eabi-4.4.0/prebuilt/linux-x86/bin/:$ANDROIDNDK:$ANDROIDSDK/tools:$PATH"
	if [ "X$ANDROIDNDKVER" == "Xr7"  ]; then
		export TOOLCHAIN_PREFIX=arm-linux-androideabi
		export TOOLCHAIN_VERSION=4.4.3
	elif [ "X$ANDROIDNDKVER" == "Xr5b" ]; then
		export TOOLCHAIN_PREFIX=arm-eabi
		export TOOLCHAIN_VERSION=4.4.0
	else
		error "Unable to configure NDK toolchain for NDK $ANDROIDNDKVER"
		exit -1
	fi

	export PATH="$ANDROIDNDK/toolchains/$TOOLCHAIN_PREFIX-$TOOLCHAIN_VERSION/prebuilt/linux-x86/bin/:$ANDROIDNDK:$ANDROIDSDK/tools:$PATH"
	export CC="$TOOLCHAIN_PREFIX-gcc $CFLAGS"
	export CXX="$TOOLCHAIN_PREFIX-g++ $CXXFLAGS"
	export AR="$TOOLCHAIN_PREFIX-ar" 
	export RANLIB="$TOOLCHAIN_PREFIX-ranlib"
	export STRIP="$TOOLCHAIN_PREFIX-strip --strip-unneeded"
	export MAKE="make -j5"

	# Use ccache ?
	which ccache &>/dev/null
	if [ $? -eq 0 ]; then
		export CC="ccache $CC"
		export CXX="ccache $CXX"
	fi
}

function pop_arm() {
	info "Leaving ARM enviromnent"
	export PATH=$OLD_PATH
	export CFLAGS=$OLD_CFLAGS
	export CXXFLAGS=$OLD_CXXFLAGS
	export CC=$OLD_CC
	export CXX=$OLD_CXX
	export AR=$OLD_AR
	export RANLIB=$OLD_RANLIB
	export STRIP=$OLD_STRIP
	export MAKE=$OLD_MAKE
}

function usage() {
	echo "Python for android - distribute.sh"
	echo "This script create a directory will all the libraries wanted"
	echo 
	echo "Usage:   ./distribute.sh [options] directory"
	echo "Example: ./distribute.sh -m 'pil kivy' dist"
	echo
	echo "Options:"
	echo
	echo "  -d directory           Name of the distribution directory"
	echo "  -h                     Show this help"
	echo "  -l                     Show a list of available modules"
	echo "  -m 'mod1 mod2'         Modules to include"
	echo "  -f                     Restart from scratch (remove the current build)"
	echo
	exit 0
}

function run_prepare() {
	info "Check enviromnent"
	if [ "X$ANDROIDSDK" == "X" ]; then
		error "No ANDROIDSDK environment set, abort"
		exit -1
	fi

	if [ "X$ANDROIDNDK" == "X" ]; then
		error "No ANDROIDNDK environment set, abort"
		exit -1
	fi

	if [ "X$ANDROIDAPI" == "X" ]; then
		export ANDROIDAPI=14
	fi

	if [ "X$ANDROIDNDKVER" == "X" ]; then
		error "No ANDROIDNDKVER enviroment set, abort"
		error "(Must be something like 'r5b', 'r7'...)"
		exit -1
	fi

	if [ "X$MODULES" == "X" ]; then
		usage
		exit 0
	fi

	debug "SDK located at $ANDROIDSDK"
	debug "NDK located at $ANDROIDNDK"
	debug "NDK version is $ANDROIDNDKVER"
	debug "API level set to $ANDROIDAPI"

	export NDKPLATFORM="$ANDROIDNDK/platforms/android-$ANDROIDAPI/arch-arm"
	export ARCH="armeabi"
	#export ARCH="armeabi-v7a" # not tested yet.

	info "Check mandatory tools"
	# ensure that some tools are existing
	for tool in md5sum tar bzip2 unzip make gcc g++; do
		which $tool &>/dev/null
		if [ $? -ne 0 ]; then
			error "Tool $tool is missing"
			exit -1
		fi
	done

	info "Distribution will be located at $DIST_PATH"
	if [ -e "$DIST_PATH" ]; then
		error "The distribution $DIST_PATH already exist"
		error "Press a key to remove it, or Control + C to abort."
		read
		try rm -rf "$DIST_PATH"
	fi
	try mkdir -p "$DIST_PATH"

	if [ $DO_CLEAN_BUILD -eq 1 ]; then
		info "Cleaning build"
		try rm -rf $BUILD_PATH
		try rm -rf $SRC_PATH/obj
		try rm -rf $SRC_PATH/libs
	fi

	# create build directory if not found
	test -d $PACKAGES_PATH || mkdir -p $PACKAGES_PATH
	test -d $BUILD_PATH || mkdir -p $BUILD_PATH
	test -d $LIBS_PATH || mkdir -p $LIBS_PATH

	# create initial files
	echo "target=android-$ANDROIDAPI" > $SRC_PATH/default.properties
	echo "sdk.dir=$ANDROIDSDK" > $SRC_PATH/local.properties
}

function in_array() {
	term="$1"
	shift
	i=0
	for key in $@; do
		if [ $term == $key ]; then
			return $i
		fi
		i=$(($i + 1))
	done
	return 255
}

function run_source_modules() {
	needed=($MODULES)
	declare -A processed
	order=()

	while [ ${#needed[*]} -ne 0 ]; do

		# pop module from the needed list
		module=${needed[0]}
		unset needed[0]
		needed=( ${needed[@]} )

		# check if the module have already been declared
		if [[ ${processed[$module]} ]]; then
			debug "Ignored $module, already processed"
			continue;
		fi

		# add this module as done
		processed[$module]=1

		# append our module at the end only if we are not exist yet
		in_array $module "${order[@]}"
		if [ $? -eq 255 ]; then
			order=( ${order[@]} $module )
		fi

		# read recipe
		debug "Read $module recipe"
		recipe=$RECIPES_PATH/$module/recipe.sh
		if [ ! -f $recipe ]; then
			error "Recipe $module does not exit"
			exit -1
		fi
		source $RECIPES_PATH/$module/recipe.sh

		# append current module deps to the needed
		deps=$(echo \$"{DEPS_$module[@]}")
		eval deps=($deps)
		if [ ${#deps[*]} -gt 0 ]; then
			debug "Module $module depend on" ${deps[@]}
			needed=( ${needed[@]} ${deps[@]} )

			# for every deps, check if it's already added to order
			# if not, add the deps before ourself
			debug "Dependency order is ${order[@]} (current)"
			for dep in "${deps[@]}"; do
				#debug "Check if $dep is in order"
				in_array $dep "${order[@]}"
				if [ $? -eq 255 ]; then
					#debug "missing $dep in order"
					# deps not found in order
					# add it before ourself
					in_array $module "${order[@]}"
					index=$?
					#debug "our $module index is $index"
					order=(${order[@]:0:$index} $dep ${order[@]:$index})
					#debug "new order is ${order[@]}"
				fi
			done
			debug "Dependency order is ${order[@]} (computed)"
		fi
	done

	MODULES="${order[@]}"
	info="Modules changed to $MODULES"
}

function run_get_packages() {
	info "Run get packages"

	for module in $MODULES; do
		# download dependencies for this module
		debug "Download package for $module"

		url="URL_$module"
		url=${!url}
		md5="MD5_$module"
		md5=${!md5}

		if [ ! -d "$BUILD_PATH/$module" ]; then
			try mkdir -p $BUILD_PATH/$module
		fi

		if [ "X$url" == "X" ]; then
			debug "No package for $module"
			continue
		fi

		filename=$(basename $url)
		do_download=1

		# check if the file is already present
		cd $PACKAGES_PATH
		if [ -f $filename ]; then

			# check if the md5 is correct
			current_md5=$(md5sum $filename | cut -d\  -f1)
			if [ "X$current_md5" == "X$md5" ]; then
				# correct, no need to download
				do_download=0
			else
				# invalid download, remove the file
				error "Module $module have invalid md5, redownload."
				rm $filename
			fi
		fi

		# download if needed
		if [ $do_download -eq 1 ]; then
			info "Downloading $url"
			try wget $url
		else
			debug "Module $module already downloaded"
		fi

		# check md5
		current_md5=$(md5sum $filename | cut -d\  -f1)
		if [ "X$current_md5" != "X$md5" ]; then
			error "File $filename md5 check failed (got $current_md5 instead of $md5)."
			error "Ensure the file is correctly downloaded, and update MD5S_$module"
			exit -1
		fi

		# if already decompress, forget it
		cd $BUILD_PATH/$module
		directory=$(get_directory $filename)
		if [ -d $directory ]; then
			continue
		fi

		# decompress
		pfilename=$PACKAGES_PATH/$filename
		info "Extract $pfilename"
		case $pfilename in
			*.tar.gz|*.tgz )
				try tar xzf $pfilename
				root_directory=$(basename $(try tar tzf $pfilename|head -n1))
				if [ "X$root_directory" != "X$directory" ]; then
					mv $root_directory $directory
				fi
				;;
			*.tar.bz2|*.tbz2 )
				try tar xjf $pfilename
				root_directory=$(basename $(try tar tjf $pfilename|head -n1))
				if [ "X$root_directory" != "X$directory" ]; then
					mv $root_directory $directory
				fi
				;;
			*.zip )
				try unzip x $pfilename
				root_directory=$(basename $(try unzip -l $pfilename|sed -n 4p|awk '{print $4}'))
				if [ "X$root_directory" != "X$directory" ]; then
					mv $root_directory $directory
				fi
				;;
		esac
	done
}

function run_prebuild() {
	info "Run prebuild"
	cd $BUILD_PATH
	for module in $MODULES; do
		fn=$(echo prebuild_$module)
		debug "Call $fn"
		$fn
	done
}

function run_build() {
	info "Run build"
	cd $BUILD_PATH
	for module in $MODULES; do
		fn=$(echo build_$module)
		debug "Call $fn"
		$fn
	done
}

function run_postbuild() {
	info "Run postbuild"
	cd $BUILD_PATH
	for module in $MODULES; do
		fn=$(echo postbuild_$module)
		debug "Call $fn"
		$fn
	done
}

function run_distribute() {
	info "Run distribute"

	cd "$DIST_PATH"

	debug "Create initial layout"
	try mkdir assets bin private res templates

	debug "Copy default files"
	try cp -a $SRC_PATH/default.properties .
	try cp -a $SRC_PATH/local.properties .
	try cp -a $SRC_PATH/build.py .
	try cp -a $SRC_PATH/buildlib .
	try cp -a $SRC_PATH/src .
	try cp -a $SRC_PATH/templates .
	try cp -a $SRC_PATH/res .
	try cp -a $SRC_PATH/blacklist.txt .

	debug "Copy python distribution"
	try cp -a $BUILD_PATH/python-install .

	debug "Copy libs"
	try mkdir -p libs/$ARCH
	try cp -a $BUILD_PATH/libs/* libs/$ARCH/

	debug "Fill private directory"
	try cp -a python-install/lib private/
	try mkdir -p private/include/python2.7
	try cp python-install/include/python2.7/pyconfig.h private/include/python2.7/

	debug "Reduce private directory from unwanted files"
	try rm -f "$DIST_PATH"/private/lib/libpython2.7.so
	try rm -rf "$DIST_PATH"/private/lib/pkgconfig
	try cd "$DIST_PATH"/private/lib/python2.7
	try find . | grep -E '*\.(py|pyc|so\.o|so\.a|so\.libs)$' | xargs rm

	# we are sure that all of theses will be never used on android (well...)
	try rm -rf test
	try rm -rf ctypes
	try rm -rf lib2to3
	try rm -rf lib-tk
	try rm -rf idlelib
	try rm -rf unittest/test
	try rm -rf json/tests
	try rm -rf distutils/tests
	try rm -rf email/test
	try rm -rf bsddb/test
	try rm -rf distutils
	try rm -rf config/libpython*.a
	try rm -rf config/python.o
	try rm -rf curses
	try rm -rf lib-dynload/_ctypes_test.so
	try rm -rf lib-dynload/_testcapi.so

	debug "Strip libraries"
	push_arm
	try find "$DIST_PATH"/private "$DIST_PATH"/libs | grep -E "*\.so$" | xargs $STRIP
	pop_arm

}

function run() {
	run_prepare
	run_source_modules
	run_get_packages

	push_arm
	debug "PATH is $PATH"
	pop_arm

	run_prebuild
	run_build
	run_postbuild
	run_distribute
	info "All done !"
}

function list_modules() {
	modules=$(find recipes -iname 'recipe.sh' | cut -d/ -f2 | sort -u | xargs echo)
	echo "Available modules: $modules"
	exit 0
}

# Do the build
while getopts ":hvlfm:d:" opt; do
	case $opt in
		h)
			usage
			;;
		l)
			list_modules
			;;
		m)
			MODULES="$OPTARG"
			;;
		d)
			DIST_PATH="$ROOT_PATH/dist/$OPTARG"
			;;
		f)
			DO_CLEAN_BUILD=1
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			exit 1
			;;

		*)
			echo "=> $OPTARG"
			;;
	esac
done

run
