#!/usr/bin/env bash
# Build script for tfz packages
set -e

VERSION="0.1.0"
PKG_NAME="tfz"
DIST_DIR="dist"

# Clean previous builds
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Create staging directory
STAGE_DIR=$(mktemp -d)
trap "rm -rf $STAGE_DIR" EXIT

echo "==> Staging files..."

# Create directory structure
mkdir -p "$STAGE_DIR/opt/tfz"
mkdir -p "$STAGE_DIR/usr/bin"

# Copy application files
cp -r bin lib Gemfile Gemfile.lock "$STAGE_DIR/opt/tfz/"

# Create wrapper script
cat > "$STAGE_DIR/usr/bin/tfz" << 'WRAPPER'
#!/usr/bin/env bash
cd /opt/tfz
exec bundle exec ruby bin/tfz "$@"
WRAPPER
chmod +x "$STAGE_DIR/usr/bin/tfz"

# Build Debian package
build_deb() {
    echo "==> Building Debian package..."
    
    DEB_DIR=$(mktemp -d)
    mkdir -p "$DEB_DIR/DEBIAN"
    cp -r "$STAGE_DIR"/* "$DEB_DIR/"
    
    cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: $PKG_NAME
Version: $VERSION
Section: utils
Priority: optional
Architecture: all
Depends: ruby (>= 3.0), ruby-bundler
Maintainer: Tim Fall <tim@example.com>
Description: Terminal-based RSS/Atom feed reader
 A beautiful terminal-based RSS/Atom feed reader with full article
 rendering, category organization, and vim-style navigation.
EOF

    cat > "$DEB_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash
cd /opt/tfz
bundle install --quiet --deployment --without development test 2>/dev/null || bundle install --quiet
EOF
    chmod +x "$DEB_DIR/DEBIAN/postinst"

    dpkg-deb --build "$DEB_DIR" "$DIST_DIR/${PKG_NAME}_${VERSION}_all.deb"
    rm -rf "$DEB_DIR"
    echo "    Created: $DIST_DIR/${PKG_NAME}_${VERSION}_all.deb"
}

# Build RPM package
build_rpm() {
    echo "==> Building RPM package..."
    
    RPM_DIR=$(mktemp -d)
    mkdir -p "$RPM_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    
    # Create tarball
    TAR_DIR="$RPM_DIR/SOURCES/$PKG_NAME-$VERSION"
    mkdir -p "$TAR_DIR"
    cp -r "$STAGE_DIR"/* "$TAR_DIR/"
    (cd "$RPM_DIR/SOURCES" && tar czf "$PKG_NAME-$VERSION.tar.gz" "$PKG_NAME-$VERSION")
    rm -rf "$TAR_DIR"
    
    cat > "$RPM_DIR/SPECS/$PKG_NAME.spec" << EOF
Name:           $PKG_NAME
Version:        $VERSION
Release:        1%{?dist}
Summary:        Terminal-based RSS/Atom feed reader
License:        MIT
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch
Requires:       ruby >= 3.0, rubygem-bundler

%description
A beautiful terminal-based RSS/Atom feed reader with full article
rendering, category organization, and vim-style navigation.

%prep
%setup -q

%install
mkdir -p %{buildroot}/opt/tfz
mkdir -p %{buildroot}/usr/bin
cp -r opt/tfz/* %{buildroot}/opt/tfz/
cp usr/bin/tfz %{buildroot}/usr/bin/

%post
cd /opt/tfz
bundle install --quiet --deployment --without development test 2>/dev/null || bundle install --quiet

%files
/opt/tfz
/usr/bin/tfz
EOF

    rpmbuild --define "_topdir $RPM_DIR" -bb "$RPM_DIR/SPECS/$PKG_NAME.spec" 2>/dev/null
    cp "$RPM_DIR"/RPMS/noarch/*.rpm "$DIST_DIR/" 2>/dev/null || true
    rm -rf "$RPM_DIR"
    echo "    Created: $DIST_DIR/${PKG_NAME}-${VERSION}-1.noarch.rpm"
}

# Build Arch package
build_arch() {
    echo "==> Building Arch package..."
    
    ARCH_DIR=$(mktemp -d)
    mkdir -p "$ARCH_DIR"
    
    # Copy staged files
    cp -r "$STAGE_DIR"/* "$ARCH_DIR/"
    
    cat > "$ARCH_DIR/PKGBUILD" << EOF
pkgname=$PKG_NAME
pkgver=$VERSION
pkgrel=1
pkgdesc="Terminal-based RSS/Atom feed reader"
arch=('any')
url="https://github.com/timfallmk/tfz"
license=('MIT')
depends=('ruby' 'ruby-bundler')

package() {
    mkdir -p "\$pkgdir/opt/tfz"
    mkdir -p "\$pkgdir/usr/bin"
    cp -r opt/tfz/* "\$pkgdir/opt/tfz/"
    cp usr/bin/tfz "\$pkgdir/usr/bin/"
}
EOF

    cat > "$ARCH_DIR/.INSTALL" << 'EOF'
post_install() {
    cd /opt/tfz
    bundle install --quiet --deployment --without development test 2>/dev/null || bundle install --quiet
}

post_upgrade() {
    post_install
}
EOF

    (cd "$ARCH_DIR" && makepkg -f 2>/dev/null)
    cp "$ARCH_DIR"/*.pkg.tar.zst "$DIST_DIR/" 2>/dev/null || true
    rm -rf "$ARCH_DIR"
    echo "    Created: $DIST_DIR/${PKG_NAME}-${VERSION}-1-any.pkg.tar.zst"
}

# Detect available package builders
echo "Building tfz v$VERSION packages..."

if command -v dpkg-deb &>/dev/null; then
    build_deb
else
    echo "    Skipping .deb (dpkg-deb not found)"
fi

if command -v rpmbuild &>/dev/null; then
    build_rpm
else
    echo "    Skipping .rpm (rpmbuild not found)"
fi

if command -v makepkg &>/dev/null; then
    build_arch
else
    echo "    Skipping .pkg.tar.zst (makepkg not found)"
fi

echo ""
echo "==> Build complete! Packages in: $DIST_DIR/"
ls -la "$DIST_DIR/" 2>/dev/null || echo "    (no packages built)"
