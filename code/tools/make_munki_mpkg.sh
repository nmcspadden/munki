#!/bin/bash
#
# Build script for munki tools, builds a distribution package.


# Defaults.
PKGID="com.googlecode.munki"
MUNKIROOT="."
# Convert to absolute path.
MUNKIROOT=`cd "$MUNKIROOT"; pwd`
OUTPUTDIR="."
# Convert to absolute path.
OUTPUTDIR=`cd "$OUTPUTDIR"; pwd`
CONFPKG=""
# add this number to Git revision index to get "build" number
# consistent with old SVN repo
MAGICNUMBER=482

# try to automagically find munki source root
TOOLSDIR=`dirname $0`
# Convert to absolute path.
TOOLSDIR=`cd "$TOOLSDIR"; pwd`
PARENTDIR=`dirname $TOOLSDIR`
PARENTDIRNAME=`basename $PARENTDIR`
if [ "$PARENTDIRNAME" == "code" ]; then
    GRANDPARENTDIR=`dirname $PARENTDIR`
    GRANDPARENTDIRNAME=`basename $GRANDPARENTDIR`
    if [ "$GRANDPARENTDIRNAME" == "Munki2" ]; then
        MUNKIROOT="$GRANDPARENTDIR"
    fi
fi

usage() {
    cat <<EOF
Usage: `basename $0` [-i id] [-r root] [-o dir] [-c package]"

    -i id       Set the base package bundle ID
    -r root     Set the munki source root
    -o dir      Set the output directory
    -c package  Include a configuration package

EOF
}


while getopts "i:r:o:c:h" option
do
    case $option in
        "i")
            PKGID="$OPTARG"
            ;;
        "r")
            MUNKIROOT="$OPTARG"
            ;;
        "o")
            OUTPUTDIR="$OPTARG"
            ;;
        "c")
            CONFPKG="$OPTARG"
            ;;
        "h" | *)
            usage
            exit 1
            ;;
    esac
done
shift $(($OPTIND - 1))

if [ $# -ne 0 ]; then
    usage
    exit 1
fi

if [ ! -d "$MUNKIROOT" ]; then
    echo "Please set the munki source root" 1>&2
    exit 1
else
    # Convert to absolute path.
    MUNKIROOT=`cd "$MUNKIROOT"; pwd`
fi

if [ ! -d "$OUTPUTDIR" ]; then
    echo "Please set the output directory" 1>&2
    exit 1
fi

# Sanity checks.
GIT=`which git`
WHICH_GIT_RESULT="$?"
if [ "$WHICH_GIT_RESULT" != "0" ]; then
    echo "Could not find git in command path. Maybe it's not installed?" 1>&2
    echo "You can get a Git package here:" 1>&2
    echo "    http://code.google.com/p/git-osx-installer/downloads/list"
    exit 1
fi
if [ ! -x "/usr/bin/pkgbuild" ]; then
    echo "pkgbuild is not installed!"
    exit 1
fi
if [ ! -x "/usr/bin/productbuild" ]; then
    echo "productbuild is not installed!"
    exit 1
fi
if [ ! -x "/usr/bin/xcodebuild" ]; then
    echo "xcodebuild is not installed!"
    exit 1
fi

# Get the munki version.
MUNKIVERS=`defaults read "$MUNKIROOT/code/client/munkilib/version" CFBundleShortVersionString`
if [ "$?" != "0" ]; then
    echo "$MUNKIROOT/code/client/munkilib/version is missing!" 1>&2
    echo "Perhaps $MUNKIROOT does not contain the munki source?"  1>&2
    exit 1
fi

cd "$MUNKIROOT"
# generate a psuedo-svn revision number for the core tools (and admin tools)
# from the list of Git revisions
GITREV=`git log -n1 --format="%H" -- code/client`
GITREVINDEX=`git rev-list --reverse HEAD | grep -n $GITREV | cut -d: -f1`
SVNREV=$(($GITREVINDEX + $MAGICNUMBER))
VERSION=$MUNKIVERS.$SVNREV

# get a psuedo-svn revision number for the metapackage
MPKGGITREV=`git log -n1 --format="%H"`
GITREVINDEX=`git rev-list --reverse HEAD | grep -n $MPKGGITREV | cut -d: -f1`
MPKGSVNREV=$(($GITREVINDEX + $MAGICNUMBER))
MPKGVERSION=$MUNKIVERS.$MPKGSVNREV

# get a pseudo-svn revision number for the launchd pkg
LAUNCHDGITREV=`git log -n1 --format="%H" -- launchd`
GITREVINDEX=`git rev-list --reverse HEAD | grep -n $LAUNCHDGITREV | cut -d: -f1`
LAUNCHDSVNREV=$(($GITREVINDEX + $MAGICNUMBER))
# Get launchd version if different
LAUNCHDVERSION=$MUNKIVERS
if [ -e "$MUNKIROOT/launchd/version.plist" ]; then
    LAUNCHDVERSION=`defaults read "$MUNKIROOT/launchd/version" CFBundleShortVersionString`
fi
LAUNCHDVERSION=$LAUNCHDVERSION.$LAUNCHDSVNREV

MPKG="$OUTPUTDIR/munkitools-$MPKGVERSION.pkg"

if [ $(id -u) -ne 0 ]; then
    cat <<EOF

            #####################################################
            ##  Please enter your sudo password when prompted  ##
            #####################################################

EOF
fi


echo "Build variables"
echo
echo "  Bundle ID: $PKGID"
echo "  Munki root: $MUNKIROOT"
echo "  Output directory: $OUTPUTDIR"
echo "  munki core tools version: $VERSION"
echo "  LaunchAgents/LaunchDaemons version: $LAUNCHDVERSION"
echo "  metapackage version: $MPKGVERSION"
echo

# Build Managed Software Center.
echo "Building Managed Software Update.xcodeproj..."
pushd "$MUNKIROOT/code/Managed Software Center" > /dev/null
/usr/bin/xcodebuild -project "Managed Software Center.xcodeproj" -alltargets clean > /dev/null
/usr/bin/xcodebuild -project "Managed Software Center.xcodeproj" -alltargets build > /dev/null
XCODEBUILD_RESULT="$?"
popd > /dev/null
if [ "$XCODEBUILD_RESULT" -ne 0 ]; then
    echo "Error building Managed Software Center.app: $XCODEBUILD_RESULT"
    exit 2
fi

if [ ! -e "$MUNKIROOT/code/Managed Software Center/build/Release/Managed Software Center.app" ]; then
    echo "Need a release build of Managed Software Center.app!"
    echo "Open the Xcode project $MUNKIROOT/code/Managed Software Center/Managed Software Center.xcodeproj and build it."
    exit 2
fi

# Build MunkiStatus
echo "Building MunkiStatus.xcodeproj..."
pushd "$MUNKIROOT/code/MunkiStatus" > /dev/null
/usr/bin/xcodebuild -project "MunkiStatus.xcodeproj" -alltargets clean > /dev/null
/usr/bin/xcodebuild -project "MunkiStatus.xcodeproj" -alltargets build > /dev/null
XCODEBUILD_RESULT="$?"
popd > /dev/null
if [ "$XCODEBUILD_RESULT" -ne 0 ]; then
    echo "Error building MunkiStatus.app: $XCODEBUILD_RESULT"
    exit 2
fi

if [ ! -e "$MUNKIROOT/code/MunkiStatus/build/Release/MunkiStatus.app" ]; then
    echo "Need a release build of MunkiStatus.app!"
    echo "Open the Xcode project $MUNKIROOT/code/MunkiStatus/MunkiStatus.xcodeproj and build it."
    exit 2
fi

# Create a PackageInfo file.
makeinfo() {
    pkg="$1"
    out="$2_$pkg"
    id="$3.$pkg"
    ver="$4"
    size="$5"
    nfiles="$6"
    restart="$7"
    major=`echo $ver | cut -d. -f1`
    minor=`echo $ver | cut -d. -f2`
    # Flat packages want a PackageInfo.
    if [ "$restart" == "restart" ]; then
        restart=' postinstall-action="restart"' # Leading space is important.
    else
        restart=""
    fi
    MSUID=`defaults read "$MUNKIROOT/code/Managed Software Center/build/Release/Managed Software Center.app/Contents/Info" CFBundleIdentifier`
    if [ "$pkg" == "app" ]; then
        app="<bundle id=\"$MSUID\"
        CFBundleIdentifier=\"$MSUID\"
        path=\"./Applications/Managed Software Center.app\"
        CFBundleVersion=\"$ver\"/>
<bundle-version>
    <bundle id=\"$MSUID\"/>
</bundle-version>"
    else
        app=""
    fi
        cat > "$out" <<EOF
<pkg-info format-version="2" identifier="$id" version="$ver" install-location="/" auth="root"$restart>
    <payload installKBytes="$size" numberOfFiles="$nfiles"/>
    $app
</pkg-info>
EOF
}


# Pre-build cleanup.
rm -rf "$MPKG"
if [ "$?" -ne 0 ]; then
    echo "Error removing $MPKG before rebuilding it."
    exit 2
fi


# Create temporary directory
PKGTMP=`mktemp -d -t munkipkg`


#########################################
## core munki tools                    ##
## /usr/local/munki, minus admin tools ##
## plus /Library/Managed Installs      ##
#########################################

echo "Creating core package template..."

# Create directory structure.
COREROOT="$PKGTMP/munki_core"
mkdir -m 1775 "$COREROOT"
mkdir -p "$COREROOT/usr/local/munki/munkilib"
chmod -R 755 "$COREROOT/usr"
# Copy command line utilities.
# edit this if list of tools changes!
for TOOL in launchapp logouthelper managedsoftwareupdate supervisor ptyexec
do
	cp -X "$MUNKIROOT/code/client/$TOOL" "$COREROOT/usr/local/munki/" 2>&1
done
# Copy python library.
cp -X "$MUNKIROOT/code/client/munkilib/"*.py "$COREROOT/usr/local/munki/munkilib/"
# Copy munki version.
cp -X "$MUNKIROOT/code/client/munkilib/version.plist" "$COREROOT/usr/local/munki/munkilib/"
# svnversion file was used when we were using subversion
# we don't need this file if we have an updated get_version method in munkicommon.py
if [ "$SVNREV" -lt "1302" ]; then
    echo $SVNREV > "$COREROOT/usr/local/munki/munkilib/svnversion"
fi

# add Build Number and Git Revision to version.plist
/usr/libexec/PlistBuddy -c "Delete :BuildNumber" "$COREROOT/usr/local/munki/munkilib/version.plist" 2>/dev/null
/usr/libexec/PlistBuddy -c "Add :BuildNumber string $SVNREV" "$COREROOT/usr/local/munki/munkilib/version.plist"
/usr/libexec/PlistBuddy -c "Delete :GitRevision" "$COREROOT/usr/local/munki/munkilib/version.plist" 2>/dev/null
/usr/libexec/PlistBuddy -c "Add :GitRevision string $GITREV" "$COREROOT/usr/local/munki/munkilib/version.plist"
# Set permissions.
chmod -R go-w "$COREROOT/usr/local/munki"
chmod +x "$COREROOT/usr/local/munki"
#chmod +x "$COREROOT/usr/local/munki/munkilib/"*.py

# Create directory structure for /Library/Managed Installs.
mkdir -m 1775 "$COREROOT/Library"
mkdir -m 755 -p "$COREROOT/Library/Managed Installs"
mkdir -m 750 -p "$COREROOT/Library/Managed Installs/Cache"
mkdir -m 750 -p "$COREROOT/Library/Managed Installs/catalogs"
mkdir -m 755 -p "$COREROOT/Library/Managed Installs/manifests"


# Create package info file.
CORESIZE=`du -sk $COREROOT | cut -f1`
NFILES=$(echo `find $COREROOT/ | wc -l`)
makeinfo core "$PKGTMP/info" "$PKGID" "$VERSION" $CORESIZE $NFILES norestart


#########################################
## admin munki tools                   ##
## /usr/local/munki admin tools        ##
#########################################

echo "Creating admin package template..."

# Create directory structure.
ADMINROOT="$PKGTMP/munki_admin"
mkdir -m 1775 "$ADMINROOT"
mkdir -p "$ADMINROOT/usr/local/munki"
chmod -R 755 "$ADMINROOT/usr"
# Copy command line admin utilities.
# edit this if list of tools changes!
for TOOL in makecatalogs makepkginfo manifestutil munkiimport
do
	cp -X "$MUNKIROOT/code/client/$TOOL" "$ADMINROOT/usr/local/munki/" 2>&1
done
# Set permissions.
chmod -R go-w "$ADMINROOT/usr/local/munki"
chmod +x "$ADMINROOT/usr/local/munki"
# make paths.d file
mkdir -p "$ADMINROOT/private/etc/paths.d"
echo "/usr/local/munki" > "$ADMINROOT/private/etc/paths.d/munki"
chmod -R 755 "$ADMINROOT/private"

# Create package info file.
ADMINSIZE=`du -sk $ADMINROOT | cut -f1`
NFILES=$(echo `find $ADMINROOT/ | wc -l`)
makeinfo admin "$PKGTMP/info" "$PKGID" "$VERSION" $ADMINSIZE $NFILES norestart



###################
## /Applications ##
###################

echo "Creating applications package template..."

# Create directory structure.
APPROOT="$PKGTMP/munki_app"
mkdir -m 1775 "$APPROOT"
mkdir -p "$APPROOT/Applications/Utilities"
chmod -R 775 "$APPROOT/Applications"
# Copy Application.
cp -R "$MUNKIROOT/code/Managed Software Center/build/Release/Managed Software Center.app" "$APPROOT/Applications/"
# Copy MunkiStatus helper app
cp -R "$MUNKIROOT/code/MunkiStatus/build/Release/MunkiStatus.app" "$APPROOT/Applications/Managed Software Center.app/Contents/Resources/"
# make sure not writeable by group or other
chmod -R go-w "$APPROOT/Applications/Managed Software Center.app"
# make a symlink for the old MSU.app
ln -s "../Managed Software Center.app" "$APPROOT/Applications/Utilities/Managed Software Update.app"
# Create package info file.
APPSIZE=`du -sk $APPROOT | cut -f1`
NFILES=$(echo `find $APPROOT/ | wc -l`)
MSUVERSION=`defaults read "$MUNKIROOT/code/Managed Software Center/build/Release/Managed Software Center.app/Contents/Info" CFBundleShortVersionString`
makeinfo app "$PKGTMP/info" "$PKGID" "$MSUVERSION" $APPSIZE $NFILES norestart


##############
## launchd ##
##############

echo "Creating launchd package template..."

# Create directory structure.
LAUNCHDROOT="$PKGTMP/munki_launchd"
mkdir -m 1775 "$LAUNCHDROOT"
mkdir -m 1775 "$LAUNCHDROOT/Library"
mkdir -m 755 "$LAUNCHDROOT/Library/LaunchAgents"
mkdir -m 755 "$LAUNCHDROOT/Library/LaunchDaemons"
# Copy launch daemons and launch agents.
cp -X "$MUNKIROOT/launchd/LaunchAgents/"*.plist "$LAUNCHDROOT/Library/LaunchAgents/"
chmod 644 "$LAUNCHDROOT/Library/LaunchAgents/"*
cp -X "$MUNKIROOT/launchd/LaunchDaemons/"*.plist "$LAUNCHDROOT/Library/LaunchDaemons/"
chmod 644 "$LAUNCHDROOT/Library/LaunchDaemons/"*
# Create package info file.
LAUNCHDSIZE=`du -sk $LAUNCHDROOT | cut -f1`
NFILES=$(echo `find $LAUNCHDROOT/ | wc -l`)
makeinfo launchd "$PKGTMP/info" "$PKGID" "$LAUNCHDVERSION" $LAUNCHDSIZE $NFILES restart


#############################
## Create metapackage root ##
#############################

echo "Creating metapackage template..."


# Create root for productbuild.
METAROOT="$PKGTMP/munki_mpkg"
mkdir -p "$METAROOT/Resources"
# Configure Distribution
DISTFILE="$METAROOT/Distribution"
PKGPREFIX="#"
# Package destination directory.
PKGDEST="$METAROOT"

# Create Distribution file.
CORETITLE=`defaults read "$MUNKIROOT/code/pkgtemplate/Resources_core/English.lproj/Description" IFPkgDescriptionTitle`
ADMINTITLE=`defaults read "$MUNKIROOT/code/pkgtemplate/Resources_admin/English.lproj/Description" IFPkgDescriptionTitle`
APPTITLE=`defaults read "$MUNKIROOT/code/pkgtemplate/Resources_app/English.lproj/Description" IFPkgDescriptionTitle`
LAUNCHDTITLE=`defaults read "$MUNKIROOT/code/pkgtemplate/Resources_launchd/English.lproj/Description" IFPkgDescriptionTitle`
COREDESC=`defaults read "$MUNKIROOT/code/pkgtemplate/Resources_core/English.lproj/Description" IFPkgDescriptionDescription`
ADMINDESC=`defaults read "$MUNKIROOT/code/pkgtemplate/Resources_admin/English.lproj/Description" IFPkgDescriptionDescription`
APPDESC=`defaults read "$MUNKIROOT/code/pkgtemplate/Resources_app/English.lproj/Description" IFPkgDescriptionDescription`
LAUNCHDDESC=`defaults read "$MUNKIROOT/code/pkgtemplate/Resources_launchd/English.lproj/Description" IFPkgDescriptionDescription`
CONFOUTLINE=""
CONFCHOICE=""
CONFREF=""
if [ ! -z "$CONFPKG" ]; then
    if [ $PKGTYPE == "flat" ]; then
        echo "Flat configuration package not implemented"
        exit 1
    else
        if [ -d "$CONFPKG/Contents/Resources/English.lproj" ]; then
            eng_resources="$CONFPKG/Contents/Resources/English.lproj"
        elif [ -d "$CONFPKG/Contents/Resources/en.lproj" ]; then
            eng_resources="$CONFPKG/Contents/Resources/en.lproj"
        else
            echo "Can't find English.lproj or en.lproj in $CONFPKG/Contents/Resources"
            exit 1
        fi
        CONFTITLE=`defaults read "$eng_resources/Description" IFPkgDescriptionTitle`
        CONFDESC=`defaults read "$eng_resources/Description" IFPkgDescriptionDescription`
        CONFID=`defaults read "$CONFPKG/Contents/Info" CFBundleIdentifier`
        CONFSIZE=`defaults read "$CONFPKG/Contents/Info" IFPkgFlagInstalledSize`
        CONFVERSION=`defaults read "$CONFPKG/Contents/Info" CFBundleShortVersionString`
        CONFBASENAME=`basename "$CONFPKG"`
    fi
    CONFOUTLINE="<line choice=\"config\"/>"
    CONFCHOICE="<choice id=\"config\" title=\"$CONFTITLE\" description=\"$CONFDESC\">
        <pkg-ref id=\"$CONFID\"/>
    </choice>"
    CONFREF="<pkg-ref id=\"$CONFID\" installKBytes=\"$CONFSIZE\" version=\"$CONFVERSION\" auth=\"Root\">${PKGPREFIX}$CONFBASENAME</pkg-ref>"
fi
cat > "$DISTFILE" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-script minSpecVersion="1.000000" authoringTool="com.apple.PackageMaker" authoringToolVersion="3.0.4" authoringToolBuild="179">
    <title>Munki - Managed software installation for OS X</title>
    <options customize="allow" allow-external-scripts="no"/>
    <domains enable_anywhere="true"/>
    <choices-outline>
        <line choice="core"/>
        <line choice="admin"/>
        <line choice="app"/>
        <line choice="launchd"/>
        $CONFOUTLINE
    </choices-outline>
    <choice id="core" title="$CORETITLE" description="$COREDESC">
        <pkg-ref id="$PKGID.core"/>
    </choice>
    <choice id="admin" title="$ADMINTITLE" description="$ADMINDESC">
        <pkg-ref id="$PKGID.admin"/>
    </choice>
    <choice id="app" title="$APPTITLE" description="$APPDESC">
        <pkg-ref id="$PKGID.app"/>
    </choice>
    <choice id="launchd" title="$LAUNCHDTITLE" description="$LAUNCHDDESC" start_selected='system.compareVersions(my.target.receiptForIdentifier("$PKGID.launchd").version, "$LAUNCHDVERSION") != 0'>
        <pkg-ref id="$PKGID.launchd"/>
    </choice>
    $CONFCHOICE
    <pkg-ref id="$PKGID.core" installKBytes="$CORESIZE" version="$VERSION" auth="Root">${PKGPREFIX}munkitools_core-$VERSION.pkg</pkg-ref>
    <pkg-ref id="$PKGID.admin" installKBytes="$ADMINSIZE" version="$VERSION" auth="Root">${PKGPREFIX}munkitools_admin-$VERSION.pkg</pkg-ref>
    <pkg-ref id="$PKGID.app" installKBytes="$APPSIZE" version="$MSUVERSION" auth="Root">${PKGPREFIX}munkitools_app-$MSUVERSION.pkg</pkg-ref>
    <pkg-ref id="$PKGID.launchd" installKBytes="$LAUNCHDSIZE" version="$VERSION" auth="Root" onConclusion="RequireRestart">${PKGPREFIX}munkitools_launchd-$LAUNCHDVERSION.pkg</pkg-ref>
    $CONFREF
</installer-script>
EOF


###################
## Set ownership ##
###################

echo "Setting ownership to root..."

sudo chown root:admin "$COREROOT" "$ADMINROOT" "$APPROOT" "$LAUNCHDROOT"
sudo chown -hR root:wheel "$COREROOT/usr"
sudo chown -hR root:admin "$COREROOT/Library"

sudo chown -hR root:wheel "$ADMINROOT/usr"
sudo chown -hR root:wheel "$ADMINROOT/private"

sudo chown -hR root:admin "$APPROOT/Applications"

sudo chown root:admin "$LAUNCHDROOT/Library"
sudo chown -hR root:wheel "$LAUNCHDROOT/Library/LaunchDaemons"
sudo chown -hR root:wheel "$LAUNCHDROOT/Library/LaunchAgents"



######################
## Run pkgbuild ##
######################
CURRENTUSER=`whoami`
for pkg in core admin app launchd; do
    case $pkg in
        "app")
            ver="$MSUVERSION"
            ;;
        "launchd")
            ver="$LAUNCHDVERSION"
            ;;
        *)
            ver="$VERSION"
            ;;
    esac
    echo "Packaging munkitools_$pkg-$ver.pkg"
    # Use pkgutil --analyze to build a component property list
    # then turn off bundle relocation
    sudo /usr/bin/pkgbuild \
        --analyze \
        --root "$PKGTMP/munki_$pkg" \
        "${PKGTMP}/munki_${pkg}_component.plist"
    if [ "$pkg" == "app" ]; then
        # change BundleIsRelocatable from true to false
        sudo /usr/libexec/PlistBuddy \
            -c 'Set :0:BundleIsRelocatable false' \
            "${PKGTMP}/munki_${pkg}_component.plist"
    fi
    # use sudo here so pkgutil doesn't complain when it tries to
    # descend into root/Library/Managed Installs/*
    sudo /usr/bin/pkgbuild \
        --root "$PKGTMP/munki_$pkg" \
        --identifier "$PKGID.$pkg" \
        --version "$ver" \
        --ownership preserve \
        --info "$PKGTMP/info_$pkg" \
        --component-plist "${PKGTMP}/munki_${pkg}_component.plist" \
        "$PKGDEST/munkitools_$pkg-$ver.pkg"
    
    if [ "$?" -ne 0 ]; then
        echo "Error packaging munkitools_$pkg-$ver.pkg before rebuilding it."
        echo "Attempting to clean up temporary files..."
        sudo rm -rf "$PKGTMP"
        exit 2
    else
        # set ownership of package back to current user
        sudo chown -R "$CURRENTUSER" "$PKGDEST/munkitools_$pkg-$ver.pkg"
    fi
done

# build distribution pkg from the components
/usr/bin/productbuild \
    --distribution "$DISTFILE" \
    --package-path "$METAROOT" \
    --resources "$METAROOT/Resources" \
    "$MPKG"
    
if [ "$?" -ne 0 ]; then
    echo "Error creating $MPKG."
    echo "Attempting to clean up temporary files..."
    sudo rm -rf "$PKGTMP"
    exit 2
fi

echo "Distribution package created at $MPKG."

echo "Removing temporary files..."
sudo rm -rf "$PKGTMP"

echo "Done."
