#!/bin/sh

# Experimental build script for dotnet3 on FreeBSD.
#
# Depends on binary blobs on onedrive.
# No guarantess whatsoever. What a mess.
#
# Also works in build jail, thanks to creating an mlock wrapper.
#
# For running dotnet reliably, mlock is required though and
# vm.max_wired needs to be increased.
#
# Hacked together in 2020 by Michael Gmelin <grembo@freebsd.org>

set -e

echo "Starting dotnet sdk build"
echo "When this fails, try re-running"

pkg install libunwind lttng-ust icu curl bash git cmake krb5 python compat11x-amd64 libinotify openssl llvm ninja

export DOTNET_CLI_TELEMETRY_OPTOUT=1

BASE=$(pwd)
DISTFILES=$BASE/distfiles
REPOS=$BASE/repos
BUILD=$BASE/build
NUPKG=$BASE/nupkg
STAGE=$BASE/stage
PATCHES=$BASE/patches
TOOLS=$BASE/tools

echo "Fetching files..."
mkdir -p $DISTFILES
if [ ! -e $DISTFILES/x ]; then
	echo "x"
	fetch -o $DISTFILES/x "https://onedrive.live.com/download?authkey=%21AKxLe8gDnxt6pKc&cid=8E0D2FB68589CE31&resid=8E0D2FB68589CE31%211534&parId=8E0D2FB68589CE31%211389"
fi

if [ ! -e $DISTFILES/y ]; then
	echo "y"
	fetch -o $DISTFILES/y "https://onedrive.live.com/download?authkey=%21ALgFyMGtkEVugwA&cid=8E0D2FB68589CE31&resid=8E0D2FB68589CE31%211535&parId=8E0D2FB68589CE31%211389"
fi

SEED_SDK=$DISTFILES/dotnet-sdk-3.1.100-freebsd-x64.tar.gz
if [ ! -e $SEED_SDK ]; then
	echo "Downloading Seed SDK 3.1.100"
	fetch -o $SEED_SDK "https://onedrive.live.com/download?authkey=%21AC5TJRRAaxDaug4&cid=8E0D2FB68589CE31&resid=8E0D2FB68589CE31%211536&parId=8E0D2FB68589CE31%211389"
fi


echo "Download sources..."

if [ ! -e $DISTFILES/coreclr.tar.gz ]; then
	fetch -o $DISTFILES/coreclr.tar.gz https://github.com/dotnet/coreclr/tarball/c5d3d75
fi

if [ ! -e $DISTFILES/corefx.tar.gz ]; then
	fetch -o $DISTFILES/corefx.tar.gz https://github.com/dotnet/corefx/tarball/8a3ffed
fi

if [ ! -e $DISTFILES/core-setup.tar.gz ]; then
	fetch -o $DISTFILES/core-setup.tar.gz https://github.com/dotnet/core-setup/tarball/4a9f85e
fi

if [ ! -e $DISTFILES/aspnetcore.tar.gz ]; then
	fetch -o $DISTFILES/aspnetcore.tar.gz https://github.com/dotnet/aspnetcore/tarball/e81033e
fi

if [ ! -e $DISTFILES/installer.tar.gz ]; then
	fetch -o $DISTFILES/installer.tar.gz https://github.com/dotnet/installer/tarball/6f74c4a
fi

if [ ! -e $DISTFILES/googletest.tar.gz ]; then
	fetch -o $DISTFILES/googletest.tar.gz https://github.com/google/googletest/tarball/4e4df22
fi

if [ ! -e $DISTFILES/MessagePack-CSharp.tar.gz ]; then
	fetch -o $DISTFILES/MessagePack-CSharp.tar.gz https://github.com/aspnet/MessagePack-CSharp/tarball/8861abd
fi

echo "Checking out repos..."
mkdir -p $REPOS
cd $REPOS
for name in coreclr corefx core-setup aspnetcore installer; do
	if [ ! -e $name ]; then
		echo $name
		git clone https://github.com/dotnet/$name.git
	fi
done

export TZ=UTC

echo "Build..."
mkdir -p $NUPKG
mkdir -p $BUILD
mkdir -p $STAGE
mkdir -p $TOOLS

if [ ! -e $BUILD/.dotnet ]; then
	mkdir $BUILD/.dotnet
	tar -xf $SEED_SDK -C $BUILD/.dotnet
fi

if [ ! -e $TOOLS/libmlockshim.so ]; then
     cc -shared -x c - -o $TOOLS/libmlockshim.so <<EOF
      #include <unistd.h>
      int mlock(const void *addr, size_t len) { return 0; }
      int munlock(const void *addr, size_t len) { return 0; }
EOF
fi

export LD_PRELOAD=$TOOLS/libmlockshim.so

echo "Building coreclr..."
if [ ! -e $NUPKG/transport.runtime.freebsd-x64.Microsoft.NETCore.TestHost.3.1.3-servicing.20118.3.nupkg ]; then
	rm -rf $BUILD/dotnet-coreclr-c5d3d75
	tar -xf $DISTFILES/coreclr.tar.gz -C $BUILD
	cd $BUILD/dotnet-coreclr-c5d3d75
	git init .
	git remote add origin https://dotnet.freebsd.org
	git config user.email ports@freebsd.org
	git add README.md
	git commit -m init
	ln -s ../.dotnet .
	./build.sh -x64 -ninja -release -skiprestore -skiptests -stripsymbols \
		/p:OfficialBuildId=20200218.3 \
		/p:ContinuousIntegrationBuild=true \
		/p:PortableBuild=true \
		/p:SourceRevisionId=c5d3d752260383fbed72ba2b4d86d82fea673c76 \
		/p:DeterministicSourcePaths=false \
		/p:PublishRepositoryUrl=false \
		/p:EmbedUntrackedSources=false \
		/p:EnableSourceLink=false \
		/p:EnableSourceControlManagerQueries=false

	for name in \
	    runtime.freebsd-x64.Microsoft.NETCore.ILAsm.3.1.3-servicing.20118.3.nupkg \
	    runtime.freebsd-x64.Microsoft.NETCore.ILDAsm.3.1.3-servicing.20118.3.nupkg \
	    runtime.freebsd-x64.Microsoft.NETCore.Jit.3.1.3-servicing.20118.3.nupkg \
	    runtime.freebsd-x64.Microsoft.NETCore.Native.3.1.3-servicing.20118.3.nupkg \
	    runtime.freebsd-x64.Microsoft.NETCore.Runtime.CoreCLR.3.1.3-servicing.20118.3.nupkg \
	    runtime.freebsd-x64.Microsoft.NETCore.TestHost.3.1.3-servicing.20118.3.nupkg \
	    transport.runtime.freebsd-x64.Microsoft.NETCore.ILAsm.3.1.3-servicing.20118.3.nupkg \
	    transport.runtime.freebsd-x64.Microsoft.NETCore.ILDAsm.3.1.3-servicing.20118.3.nupkg \
	    transport.runtime.freebsd-x64.Microsoft.NETCore.Jit.3.1.3-servicing.20118.3.nupkg \
	    transport.runtime.freebsd-x64.Microsoft.NETCore.Native.3.1.3-servicing.20118.3.nupkg \
	    transport.runtime.freebsd-x64.Microsoft.NETCore.Runtime.CoreCLR.3.1.3-servicing.20118.3.nupkg \
	    transport.runtime.freebsd-x64.Microsoft.NETCore.TestHost.3.1.3-servicing.20118.3.nupkg \
	    ; do
			cp bin/Product/FreeBSD.x64.Release/.nuget/pkg/$name $NUPKG/.
	done
	set +e
	cp -n bin/Product/FreeBSD.x64.Release/.nuget/pkg/*.nupkg $NUPKG/.
	set -e
fi

echo "Building corefx..."
if [ ! -e $NUPKG/runtime.freebsd-x64.Microsoft.Private.CoreFx.NETCoreApp.4.7.0-servicing.20120.1.nupkg ]; then
	rm -rf $BUILD/dotnet-corefx-8a3ffed
	tar -xf $DISTFILES/corefx.tar.gz -C $BUILD
	cd $BUILD/dotnet-corefx-8a3ffed
	git init .
	git remote add origin https://dotnet.freebsd.org
	git config user.email ports@freebsd.org
	git add README.md
	git commit -m init
	patch -p1 <$PATCHES/corefx.patch
        sed -i '' -e "s|/home/build/nupkg|$NUPKG|g" NuGet.config
	mkdir -p artifacts/bin/testhost/netcoreapp-FreeBSD-Release-x64/
	ln -s ../.dotnet .

	./build.sh --configuration Release --arch x64 --os FreeBSD \
		/p:UpdateRuntimeFiles=true \
		/p:PortableBuild=true \
		/p:OfficialBuildId=20200220.1 \
		/p:ContinuousIntegrationBuild=true \
		/p:SourceRevisionId=8a3ffed558ddf943c1efa87d693227722d6af094 \
		/p:DeterministicSourcePaths=false \
		/p:PublishRepositoryUrl=false \
		/p:EmbedUntrackedSources=false \
		/p:EnableSourceLink=false \
		/p:EnableSourceControlManagerQueries=false

	for name in \
	    runtime.freebsd-x64.Microsoft.Private.CoreFx.NETCoreApp.4.7.0-servicing.20120.1.nupkg \
	    ; do
		cp artifacts/packages/Release/NonShipping/$name $NUPKG/.
	done
fi


echo "Building core-setup..."
if [ ! -e $STAGE/dotnet-runtime-3.1.3-freebsd-x64.tar.gz ]; then
	rm -rf $BUILD/dotnet-core-setup-4a9f85e
	tar -xf $DISTFILES/core-setup.tar.gz -C $BUILD
	cd $BUILD/dotnet-core-setup-4a9f85e
	git init .
	git remote add origin https://dotnet.freebsd.org
	git config user.email ports@freebsd.org
	git add README.md
	git commit -m init
	patch -p1 <$PATCHES/core-setup.patch
        sed -i '' -e "s|/home/build/nupkg|$NUPKG|g" NuGet.config
	ln -s ../.dotnet .

	./build.sh --configuration Release /p:OSGroup=FreeBSD \
		/p:PortableBuild=true /p:OfficialBuildId=20200228.1 \
		/p:ContinuousIntegrationBuild=true /nr:false \
		/p:SourceRevisionId=4a9f85e9f89d7f686fef2ae2109d876b1e2eed2a \
		/p:DeterministicSourcePaths=false \
		/p:PublishRepositoryUrl=false \
		/p:EmbedUntrackedSources=false \
		/p:EnableSourceLink=false \
		/p:EnableSourceControlManagerQueries=false

	for name in \
	    runtime.freebsd-x64.Microsoft.NETCore.App.3.1.3-servicing.20128.1.nupkg \
	    ; do
		cp artifacts/packages/Release/NonShipping/$name $NUPKG/.
	done

	for name in \
	    Microsoft.NETCore.App.Host.freebsd-x64.3.1.3.nupkg \
	    Microsoft.NETCore.App.Runtime.freebsd-x64.3.1.3.nupkg \
	    runtime.freebsd-x64.Microsoft.NETCore.DotNetAppHost.3.1.3.nupkg \
	    runtime.freebsd-x64.Microsoft.NETCore.DotNetHost.3.1.3.nupkg \
	    runtime.freebsd-x64.Microsoft.NETCore.DotNetHostPolicy.3.1.3.nupkg \
	    runtime.freebsd-x64.Microsoft.NETCore.DotNetHostResolver.3.1.3.nupkg \
	    ; do
		cp artifacts/packages/Release/Shipping/$name $NUPKG/.
	done

	set +e
	cp -n artifacts/packages/Release/Shipping/*freebsd*3.1.3.nupkg $NUPKG/.
	set -e

	for name in \
	    dotnet-runtime-3.1.3-freebsd-x64.tar.gz \
	    ; do
		cp artifacts/packages/Release/Shipping/$name $STAGE/.
	done
fi

if  [ ! -e $BUILD/.dotnet/host/fxr/3.1.3/libhostfxr.so ]; then
	tar -xf $STAGE/dotnet-runtime-3.1.3-freebsd-x64.tar.gz -C $BUILD/.dotnet
fi


echo "Building aspnetcore..."
# Warns:
#/root/dotnet/build/.dotnet/sdk/3.1.100/Microsoft.Common.CurrentVersion.targets(2106,5): warning MSB3277: Found conflicts between different versions of "System.IO.Pipelines" that could not be resolved.  These reference conflicts are listed in the build log when log verbosity is set to detailed. [/root/dotnet/build/dotnet-aspnetcore-e81033e/src/Framework/ref/Microsoft.AspNetCore.App.Ref.csproj]
if [ ! -e $STAGE/aspnetcore-runtime-internal-3.1.3-freebsd-x64.tar.gz ]; then
	rm -rf $BUILD/dotnet-aspnetcore-e81033e
	tar -xf $DISTFILES/aspnetcore.tar.gz -C $BUILD
	cd $BUILD/dotnet-aspnetcore-e81033e

	mkdir -p artifacts/obj/Microsoft.AspNetCore.App.Runtime
	cp $STAGE/dotnet-runtime-3.1.3-freebsd-x64.tar.gz \
		artifacts/obj/Microsoft.AspNetCore.App.Runtime/

	rmdir src/submodules/googletest
	rmdir src/submodules/MessagePack-CSharp
	tar -xf $DISTFILES/googletest.tar.gz -C src/submodules
	tar -xf $DISTFILES/MessagePack-CSharp.tar.gz -C src/submodules
	mv src/submodules/aspnet-MessagePack-CSharp-8861abd \
		src/submodules/MessagePack-CSharp
	mv src/submodules/google-googletest-4e4df22 \
		src/submodules/googletest

	git init .
	git remote add origin https://dotnet.freebsd.org
	git config user.email ports@freebsd.org
	git add README.md
	git commit -m init
	patch -p1 <$PATCHES/aspnetcore.patch
        sed -i '' -e "s|/home/build/nupkg|$NUPKG|g" NuGet.config

	ln -s ../.dotnet .

	./build.sh --restore \
		-c Release --arch x64 --os-name freebsd --ci /p:OfficialBuildId=20200313.14 \
		/p:SourceRevisionId=e81033e094d4663ffd227bb4aed30b76b0631e6d \
		/p:DeterministicSourcePaths=false \
		/p:PublishRepositoryUrl=false \
		/p:EmbedUntrackedSources=false \
		/p:EnableSourceLink=false \
		/p:EnableSourceControlManagerQueries=false

	./build.sh --build \
		-c Release --arch x64 --os-name freebsd --ci /p:OfficialBuildId=20200313.14 \
		/p:SourceRevisionId=e81033e094d4663ffd227bb4aed30b76b0631e6d \
		/p:DeterministicSourcePaths=false \
		/p:PublishRepositoryUrl=false \
		/p:EmbedUntrackedSources=false \
		/p:EnableSourceLink=false \
		/p:EnableSourceControlManagerQueries=false

	./build.sh --pack \
		-c Release --arch x64 --os-name freebsd --ci /p:OfficialBuildId=20200313.14 \
		/p:SourceRevisionId=e81033e094d4663ffd227bb4aed30b76b0631e6d \
		/p:DeterministicSourcePaths=false \
		/p:PublishRepositoryUrl=false \
		/p:EmbedUntrackedSources=false \
		/p:EnableSourceLink=false \
		/p:EnableSourceControlManagerQueries=false


	for name in \
	    Microsoft.AspNetCore.App.Runtime.freebsd-x64.3.1.3.nupkg \
	    ; do
		cp artifacts/packages/Release/Shipping/$name $NUPKG/.
	done

	for name in \
	    aspnetcore-runtime-internal-3.1.3-freebsd-x64.tar.gz \
	    ; do
		cp artifacts/installers/Release/$name $STAGE/.
	done
fi

echo "Building installer..."
if [ ! -e $STAGE/dotnet-sdk-3.1.103-freebsd-x64.tar.gz ]; then
	rm -rf $BUILD/dotnet-installer-6f74c4a
	tar -xf $DISTFILES/installer.tar.gz -C $BUILD
	cd $BUILD/dotnet-installer-6f74c4a

	DOWN=$(pwd)/artifacts/obj/redist/Release/downloads
	mkdir -p $DOWN
	cp $STAGE/dotnet-runtime-3.1.3-freebsd-x64.tar.gz $DOWN/.
	cp $STAGE/aspnetcore-runtime-internal-3.1.3-freebsd-x64.tar.gz \
		$DOWN/.
	#touch $DOWN/dotnet-runtime-2.1.0-freebsd-x64.tar.gz

	git init .
	git remote add origin https://dotnet.freebsd.org
	git config user.email ports@freebsd.org
	git add README.md
	git commit -m init
	patch -p1 <$PATCHES/installer.patch
        sed -i '' -e "s|/home/build/nupkg|$NUPKG|g" NuGet.config

	ln -s ../.dotnet .

	./build.sh --configuration Release /p:PortableBuild=true \
		/p:OfficialBuildId=20200317.2 \
		/p:ContinuousIntegrationBuild=true \
		/p:DisableSourceLink=true /nr:false \
		/p:SourceRevisionId=6f74c4a1dd4fd0cc49eec7a28984476ed14d09d9 \
		/p:DeterministicSourcePaths=false \
		/p:PublishRepositoryUrl=false \
		/p:EmbedUntrackedSources=false \
		/p:EnableSourceLink=false \
		/p:EnableSourceControlManagerQueries=false

	for name in \
	    dotnet-sdk-3.1.103-freebsd-x64.tar.gz \
	    ; do
		cp artifacts/packages/Release/Shipping/$name $STAGE/.
	done
fi

# Done
echo "Done"
