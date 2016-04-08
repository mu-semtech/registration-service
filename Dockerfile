FROM semtech/mu-sinatra-template:1.2.0-ruby2.1

MAINTAINER Erika Pauwels <erika.pauwels@gmail.com>

ENV MU_AUTO_LOGIN_ON_REGISTRATION false

# ONBUILD of mu-sinatra-template takes care of everything