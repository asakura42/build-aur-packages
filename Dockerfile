FROM archlinux:latest

# Install build dependencies and yay prerequisites.
# Note: update (-u) so that the newly installed tools use up-to-date packages.
RUN pacman -Syu --noconfirm base-devel git sudo

# Patch makepkg to allow running as root; see
# https://www.reddit.com/r/archlinux/comments/6qu4jt/how_to_run_makepkg_in_docker_container_yes_as_root/
RUN sed -i 's,exit $E_ROOT,echo but you know what you do,' /usr/bin/makepkg

RUN sed -i 's/SKIPPGPCHECK=0/SKIPPGPCHECK=1/' /usr/bin/makepkg

# Add the GPG key for 6BC26A17B9B7018A.
COPY gpg_key_6BC26A17B9B7018A.gpg.asc /tmp/

COPY update_repository.sh /

# Create a local user for building since aur tools should be run as a normal user.
RUN \
    groupadd builder && \
    useradd -m -g builder builder && \
    echo 'builder ALL = NOPASSWD: ALL' > /etc/sudoers.d/builder_pacman

USER builder

# Import GPG key and install yay.
RUN \
    gpg --import /tmp/gpg_key_6BC26A17B9B7018A.gpg.asc && \
    cd /tmp/ && \
    git clone https://aur.archlinux.org/yay.git && \
    cd yay && \
    makepkg -si --noconfirm && \
    mkdir /home/builder/workspace && \
    cp /tmp/yay/*.pkg.tar.zst /home/builder/workspace/ && \
    repo-add /home/builder/workspace/aurci2.db.tar.gz /home/builder/workspace/yay-*.pkg.tar.zst

USER root
# Note: GitHub Actions require the Dockerfile to be run as root, so do not
#       switch back to the unprivileged user.
#       Use `sudo --user <user> <command>` to run a command as this user.

# Register the local repository with pacman.
RUN \
    echo "# local repository (required by yay)" >> /etc/pacman.conf && \
    echo "[aurci2]" >> /etc/pacman.conf && \
    echo "SigLevel = Optional TrustAll" >> /etc/pacman.conf && \
    echo "Server = file:///home/builder/workspace" >> /etc/pacman.conf && \
    echo "[archlinuxcn]" >> /etc/pacman.conf && \
    echo "Server = https://repo.archlinuxcn.org/\$arch" >> /etc/pacman.conf && \
    pacman -Sy && \
    pacman --noconfirm -S archlinux-keyring && \
    pacman -S --noconfirm archlinuxcn-keyring && \
    pacman -Syu --noconfirm

CMD ["/update_repository.sh"]
