# Registration microservice
Registration microservice using a triple store in the backend

## Running the registration microservice
    docker run --name mu-registration \
        -p 80:80 \
        --link my-triple-store:database \
        -d semtech/mu-registration-service
        
The triple store used in the backend is linked to the registration service container as `database`. If you configure another SPARQL endpoint URL through `MU_SPARQL_ENDPOINT` update the link name accordingly. Make sure the registration service is able to execute update queries against this store.

To strengthen the password hashing, you can configure an application wide salt through the `MU_APPLICATION_SALT` environment variable. This salt will be concatenated with a salt generated per user to hash the user passwords. By default the application wide salt is not set. If you configure this salt, make sure to configure the [login microservice](https://github.com/mu-semtech/login-service) with the same salt.

The `MU_AUTO_LOGIN_ON_REGISTRATION` environment variable (default: `false`) specifies whether the new user should be logged in automatically at the end of the registration request.

The `MU_APPLICATION_GRAPH` environment variable (default: `http://mu.semte.ch/application`) specifies the graph in the triple store the login service will work in.

