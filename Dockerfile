#
# Copyright (C) 2019 - 2020 Rabobank Nederland
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

FROM phusion/baseimage:0.11

RUN apt-get update && apt-get install -y --no-install-recommends \
       openjdk-11-jre-headless

RUN useradd -ms /bin/bash tomcat
RUN usermod -p '*' tomcat

##################################################
# Begin install tomcat
#
# copied from https://raw.githubusercontent.com/docker-library/tomcat/5a8577af736ff76ade0afe2f46d03fc6aed43ce1/9.0/jdk11/openjdk-slim/Dockerfile
##################################################
ENV CATALINA_HOME /usr/local/tomcat
ENV PATH $CATALINA_HOME/bin:$PATH
RUN mkdir -p "$CATALINA_HOME"

WORKDIR $CATALINA_HOME

# let "Tomcat Native" live somewhere isolated
ENV TOMCAT_NATIVE_LIBDIR $CATALINA_HOME/native-jni-lib
ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH:+$LD_LIBRARY_PATH:}$TOMCAT_NATIVE_LIBDIR

ENV TOMCAT_MAJOR 9
ENV TOMCAT_VERSION 9.0.33
ENV TOMCAT_SHA512 caaed46e47075aff5cb97dfef0abe7fab7897691f2e81a2660c3c59f86df44d5894a5136188808e48685919ca031acd541da97c4aba2512e0937455972004a2b

RUN set -eux; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        dirmngr \
        wget ca-certificates \
    ; \
    \
    ddist() { \
        local f="$1"; shift; \
        local distFile="$1"; shift; \
        local success=; \
        local distUrl=; \
        for distUrl in \
# https://issues.apache.org/jira/browse/INFRA-8753?focusedCommentId=14735394#comment-14735394
            'https://www.apache.org/dyn/closer.cgi?action=download&filename=' \
# if the version is outdated (or we're grabbing the .asc file), we might have to pull from the dist/archive :/
            https://www-us.apache.org/dist/ \
            https://www.apache.org/dist/ \
            https://archive.apache.org/dist/ \
        ; do \
            if wget -O "$f" "$distUrl$distFile" && [ -s "$f" ]; then \
                success=1; \
                break; \
            fi; \
        done; \
        [ -n "$success" ]; \
    }; \
    \
    ddist 'tomcat.tar.gz' "tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz"; \
    echo "$TOMCAT_SHA512 *tomcat.tar.gz" | sha512sum --strict --check -; \
    ddist 'tomcat.tar.gz.asc' "tomcat/tomcat-$TOMCAT_MAJOR/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz.asc"; \
    tar -xf tomcat.tar.gz --strip-components=1; \
    rm bin/*.bat; \
    rm tomcat.tar.gz*;

# fix permissions (especially for running as non-root)
# https://github.com/docker-library/tomcat/issues/35
RUN chmod -R +rX .; \
    chmod 777 logs temp work

EXPOSE 8080

##################################################
# End install tomcat
##################################################

##################################################
# Add script for starting tomcat as runit service
##################################################
RUN mkdir /etc/service/tomcat
ADD config/service/run.sh /etc/service/tomcat/run
RUN chmod +x /etc/service/tomcat/run
    

ENV PATH $PATH:$CATALINA_HOME/bin
##################################################
# SSH
##################################################
RUN rm -f /etc/service/sshd/down && /etc/my_init.d/00_regen_ssh_host_keys.sh > /dev/nul 2>&1
RUN mkdir -p /root/.ssh
#ADD id_rsa.pub /tmp/id_rsa.pub
#RUN cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys && rm -f /tmp/id_rsa.pub
RUN sed -i -e s/^#*LoginGraceTime.*/LoginGraceTime\ 2m/ \
           -e s/^#*PermitRootLogin.*/PermitRootLogin\ yes/ \
           -e s/^#*StrictModes.*/StrictModes\ yes/ /etc/ssh/sshd_config \
           && echo "root:root" | chpasswd \
           && ssh-keygen -A
      
EXPOSE 22