### Setup mongodb scripts

Features:

 * 2 shards
 * each shard contains 3 repliate set
 * 3 config servers
 * automate add members to primiary
 * automate add shards 
 * support windows/osx/linux 
 
**remind**：This script is intended for local development.
 
 data base will be created at C:\data in windows and ./data in other systems
 
> install nodejs first 

then 

```sh
$ npm i -g coffeescript shelljs

```

####Command provide:

start up startUpMongo
```sh
shjs setup-Mongo.coffee startUpMongo
```

add primiary 
```sh
shjs setup-Mongo.coffee addSettings
```

startConfigServer 
```sh
shjs setup-Mongo.coffee startConfigServer
```

startMongos
```sh
shjs setup-Mongo.coffee startMongos
```

addShards
```sh
shjs setup-Mongo.coffee addShards
```


run all process at once
```sh
shjs setup-Mongo.coffee
```


free to modify yourself