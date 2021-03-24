FROM centos:centos8
RUN yum install -y epel-release
RUN yum makecache
RUN yum groupinstall -y "Development Tools"
RUN yum config-manager --set-enabled powertools
RUN yum install -y fileutils sudo lynx lftp wget perl texinfo chrpath socat python3-pip SDL-devel xterm python2
RUN yum install -y openssh-server lsof java-1.8.0-openjdk libXtst-devel libXt-devel cups-devel freetype-devel glibc-locale-source glibc-langpack-en maven ant
RUN alternatives --set python /usr/bin/python2

#RUN ln -s /usr/bin/python3.6 /usr/bin/python3

RUN dnf -y module disable container-tools
RUN dnf -y install 'dnf-command(copr)'
RUN dnf -y copr enable rhcontainerbot/container-selinux
RUN curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/CentOS_8/devel:kubic:libcontainers:stable.repo
RUN dnf -y install buildah

RUN yum clean all
RUN localedef -i en_US -f UTF-8 en_US.UTF-8

#ARG VERSION=4.3
ARG VERSION=3.14

RUN curl --create-dirs -fsSLo /usr/share/jenkins/agent.jar https://repo.jenkins-ci.org/public/org/jenkins-ci/main/remoting/${VERSION}/remoting-${VERSION}.jar \
  && chmod 755 /usr/share/jenkins \
  && chmod 644 /usr/share/jenkins/agent.jar \
  && ln -sf /usr/share/jenkins/agent.jar /usr/share/jenkins/slave.jar

COPY jenkins-slave /usr/local/bin/jenkins-slave
RUN chmod a+x /usr/local/bin/jenkins-slave


ENV JENKINS_HOME /home/jenkins/agent
RUN echo "root:admin" | chpasswd 

RUN mkdir -p /home/jenkins

# update sshd settings, create jenkins user, set jenkins user pw, generate ssh keys 
RUN sed -i 's|session    required     pam_loginuid.so|session    optional     pam_loginuid.so|g' /etc/pam.d/sshd \
    && mkdir -p /var/run/sshd \
    && useradd  -d "$JENKINS_HOME" -u 5107 -m -s /bin/bash jenkins \
    && echo "jenkins:jenkins" | chpasswd \
    && groupadd -g 1051 build \
    && groupadd -g 5009 cvsusers \
    && groupadd -g 5109 gitcge7 \
    && groupadd -g 5113 gitcgx \
    && groupadd -g 5117 gitcommon \
    && groupadd -g 5110 gitmvl \
    && usermod -a -G build,cvsusers,gitcge7,gitcgx,gitcommon,gitmvl jenkins \
    && /usr/bin/ssh-keygen -A \
    && echo export JAVA_HOME="/`alternatives  --display java | grep best | cut -d "/" -f 2-6`" >> /etc/environment

RUN chmod +w /etc/sudoers; echo "jenkins	ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers; chmod -w /etc/sudoers
RUN sed -i -e 's/Defaults    requiretty.*/ #Defaults    requiretty/g' /etc/sudoers
RUN ln -s java-1.8.0 /usr/lib/jvm/java-1.8.0-openjdk

RUN mkdir -p /root/.ssh
COPY authorized_keys /root/.ssh
COPY i18n /etc/sysconfig/i18n
COPY limits-90-nproc.conf /etc/security/limits.d/90-nproc.conf

RUN touch $JENKINS_HOME/.gitconfig; chown -R jenkins:jenkins $JENKINS_HOME 
USER jenkins
RUN git config --global user.email "jenkins@mvista.com"
RUN git config --global user.name "Jenkins Continuous Build server"

USER root
RUN ln -s $JENKINS_HOME /var/jenkins_home
# Adjust storage.conf to enable Fuse storage.
ADD https://raw.githubusercontent.com/containers/buildah/master/contrib/buildahimage/stable/containers.conf /etc/containers/

RUN chmod 644 /etc/containers/containers.conf; sed -i -e 's|^#mount_program|mount_program|g' -e '/additionalimage.*/a "/var/lib/shared",' -e 's|^mountopt[[:space:]]*=.*$|mountopt = "nodev,fsync=0"|g' /etc/containers/storage.conf
RUN mkdir -p /var/lib/shared/overlay-images /var/lib/shared/overlay-layers /var/lib/shared/vfs-images /var/lib/shared/vfs-layers; touch /var/lib/shared/overlay-images/images.lock; touch /var/lib/shared/overlay-layers/layers.lock; touch /var/lib/shared/vfs-images/images.lock; touch /var/lib/shared/vfs-layers/layers.lock

# Define uid/gid ranges for our user https://github.com/containers/buildah/issues/3053
RUN echo jenkins:100000:65536 > /etc/subuid \
 && echo jenkins:100000:65536 > /etc/subgid

# Set an environment variable to default to chroot isolation for RUN
# instructions and "buildah run".
ENV BUILDAH_ISOLATION=chroot

# Standard SSH port 
EXPOSE 22 
#CMD ["/usr/sbin/sshd", "-D"]
CMD ["/usr/local/bin/jenkins-slave"]


