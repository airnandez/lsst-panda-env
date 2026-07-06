FROM almalinux:9.8

#
# Update the operating system
#
RUN yum update --quiet --assumeyes

#
# Install prerequisites
#
RUN yum install --quiet --assumeyes unzip wget

#
# Create unprivileged user
#
ENV username="lsstsw"
RUN useradd --create-home --uid 1000 --user-group --home-dir /home/${username} ${username}
USER ${username}

CMD /bin/bash
