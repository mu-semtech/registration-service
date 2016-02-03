FROM semtech/mu-sinatra-template:ruby-2.1-latest

MAINTAINER Erika Pauwels <erika.pauwels@gmail.com>

ENV MU_AUTO_LOGIN_ON_REGISTRATION false

# ONBUILD of mu-sinatra-template takes care of everything