# Registration microservice
Registration microservice using a triple store in the backend

## Running the registration microservice
    docker run --name mu-registration \
        -p 80:80 \
        --link my-triple-store:database \
        -e MU_APPLICATION_GRAPH=http://mu.semte.ch/app \
        -e MU_APPLICATION_SALT=mysupersecretsaltchangeme \
	-d semtech/mu-registration-service
        
The triple store used in the backend is linked to the registration service container as `database`. Make sure the registration service is able to execute update queries against this store.

The `MU_APPLICATION_GRAPH` environment variable specifies the graph in the triple store the registration service will work in.

The `MU_APPLICATION_SALT` environment variable specifies (part of) the salt used to hash the user passwords. Configure the [login microservice](https://github.com/mu-semtech/login-service) with the same salt.

