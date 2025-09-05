FROM semtech/mu-ruby-template:3.2.1

LABEL maintainer="erika.pauwels@gmail.com"

ENV MU_AUTO_LOGIN_ON_REGISTRATION=false
ENV MU_APPLICATION_SALT=
ENV USERS_GRAPH=http://mu.semte.ch/application
ENV SESSIONS_GRAPH=http://mu.semte.ch/application
ENV ALLOW_MU_AUTH_SUDO=true
