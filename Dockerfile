FROM centos:centos7

RUN yum install --quiet --assumeyes wget curl unzip

ENV username="lsstsw"
RUN useradd --create-home --uid 1000 --user-group --home-dir /home/${username} ${username}
USER ${username}

CMD /bin/bash