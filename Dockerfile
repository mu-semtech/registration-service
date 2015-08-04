FROM erikap/ruby-sinatra:ruby-2.1-latest

ADD . /usr/src/app

RUN cd /usr/src/app \
    && bundle install --without development test