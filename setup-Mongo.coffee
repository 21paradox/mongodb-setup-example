require('shelljs/global')
fs = require('fs')
path = require('path')
require('shelljs/make')

# mac/windows/linux https://nodejs.org/api/process.html#process_process_platform
sys = process.platform

getPath = (str) -> path.resolve(__dirname, str)

if sys is "win32"
	mongoPath = 'C:/"Program Files"/MongoDB/Server/3.0/bin/mongod.exe'
	mongosPath = 'C:/"Program Files"/MongoDB/Server/3.0/bin/mongos.exe'
	
	mongoConfigs = {
		shards: {
			"rs0": [
				{ port: 10050, path: getPath("C:\\data\\db1"), primiary: true, host: "127.0.0.1" }, 
				{ port: 10051, path: getPath("C:\\data\\db2"), host: "127.0.0.1" }, 
				{ port: 10052, path: getPath("C:\\data\\db3"), host: "127.0.0.1" }
			],
			"rs1": [
				{ port: 10060, path: getPath("C:\\data\\db4"), primiary: true, host: "127.0.0.1" }, 
				{ port: 10061, path: getPath("C:\\data\\db5"), host: "127.0.0.1" }, 
				{ port: 10062, path: getPath("C:\\data\\db6"), host: "127.0.0.1" }
			]
		},
		configServer: [
			{ port: 10040, path: getPath("C:\\data\\configsvr1"), primiary: true, host: "127.0.0.1" }, 
			{ port: 10041, path: getPath("C:\\data\\configsvr2"), host: "127.0.0.1" }, 
			{ port: 10042, path: getPath("C:\\data\\configsvr3"), host: "127.0.0.1" }
		],
		mongos: {
			port: 10033
		}
	}
	
	
else
	mongoPath = "mongod"
	mongosPath = "mongos"
	
	getPath = (str) ->
		return path.resolve(__dirname, str)

	mongoConfigs = {
		shards: {
			"rs0": [
				{ port: 10050, path: getPath("./data/db1"), primiary: true, host: "127.0.0.1" }, 
				{ port: 10051, path: getPath("./data/db2"), host: "127.0.0.1" }, 
				{ port: 10052, path: getPath("./data/db3"), host: "127.0.0.1" }
			],
			"rs1": [
				{ port: 10060, path: getPath("./data/db4"), primiary: true, host: "127.0.0.1" }, 
				{ port: 10061, path: getPath("./data/db5"), host: "127.0.0.1" }, 
				{ port: 10062, path: getPath("./data/db6"), host: "127.0.0.1"}
			]
		},
		configServer: [
			{ port: 10040, path: getPath("./data/configsvr1"), primiary: true, host: "127.0.0.1" }, 
			{ port: 10041, path: getPath("./data/configsvr2"), host: "127.0.0.1" }, 
			{ port: 10042, path: getPath("./data/configsvr3"), host: "127.0.0.1" }
		],
		mongos: {
			port: 10033
		}
	}


###
	startMongodb and config server
###

# replace linebreak and indent
inlineTemplate = (template) ->
	template = template.replace(/\n/g, " ")
	template = template.replace(/\t/g, " ")
	return "\"" + template + "\"";

# set replacate configs, use single quote
configJsExpression = (setConfigs, setname) ->
	
	template = """
	(function(){
		
		var config = {
			_id: '#{setname}',
			members: [
				{ _id: 0, host: '#{setConfigs[0].host}:#{setConfigs[0].port}' },
				{ _id: 1, host: '#{setConfigs[1].host}:#{setConfigs[1].port}' },
				{ _id: 2, host: '#{setConfigs[2].host}:#{setConfigs[2].port}' }
			]
		};
		
		var status = rs.status();
		
		if (status.ok === 1) {
			rs.reconfig(config);
		} else if (status.ok === 0 && status.code === 94) {
			rs.initiate(config);
		}
		
	})();
	"""
	return inlineTemplate(template)

# start ...
startMongo = ({path, port}, setname) ->
	#fs.mkdirSync(path) if not fs.existsSync(path)
	mkdir "-p", path
	#console.log path, port, setname, "init"
	new Promise (resolve) ->
		# http://docs.mongodb.org/manual/reference/program/mongod/
		#initProcess = exec("#{mongoPath} --config #{__dirname}/mongod.conf --port #{port} --dbpath #{path}", { async: true, silent: true })
		initProcess = exec("#{mongoPath} --replSet #{setname} --port #{port} --dbpath #{path}", { async: true, silent: true })
		initProcess.stdout.on("data", (data) ->
			if data.match(/waiting for connections on port/) or data.match(/connection accepted/)
				#console.log path, port, setname, "done"
				resolve(port)
		)

# start mutiple mongo, return object containing promises
startMongoInstances = (mongoConfigs) ->
	mongoInstances = {}

	for setname, setInfos of mongoConfigs.shards
		mongoInstances[setname] = []
		for setInfo in setInfos
			mongoInstances[setname].push startMongo(setInfo, setname)
	return mongoInstances

# add shards configs
addReplSetConfigs = (setname, setInfos) ->

	port = (p for p in setInfos when p.primiary is true)[0].port
	jsToEval = configJsExpression(setInfos, setname)

	new Promise (resolve) ->
		initProcess = exec "mongo --eval #{jsToEval} --port #{port} ", { async: true, silent: false }, (data) ->
			resolve()
			console.log "#{setname} setup complete"

# setup config server
startConfigServer = ({port, path}) ->
	new Promise (resolve) ->
		mkdir "-p", path
		initProcess = exec("#{mongoPath} --port #{port} --dbpath #{path} --configsvr", { async: true, silent: true })
		initProcess.stdout.on("data", (data) ->
			if data.match(/waiting for connections on port/)
				resolve(port)
				console.log "setup config server complete"
		)

# setup config servers
addCfgServers = (mongoConfigs) ->
	for config in mongoConfigs.configServer
		startConfigServer(config)
		
# add config server to mongos
addCfgDBToMongos = (mongoConfigs) ->
	
	configdbArr = []
	
	for config in mongoConfigs.configServer
		configdbArr.push(config.host + ':' + config.port)
	
	port = mongoConfigs.mongos.port
	
	new Promise (resolve) ->
		#http://docs.mongodb.org/manual/reference/program/mongos/
		initProcess = exec("#{mongosPath} --port #{port} --configdb #{configdbArr.join(',')}", { async: true, silent: true })
		initProcess.stdout.on("data", (data) ->
			if data.match(/waiting for connections on port/)
				resolve(port)
				console.log "setup mongos complete"
		)

# add shard to mongos use single quote
# addShardTemplate = inlineTemplate("""
# 	(function(){
# 		var result = sh.addShard('rs0/127.0.0.1:10050');
# 		print(JSON.stringify(result));
# 		var result1 = sh.addShard('rs1/127.0.0.1:10060');
# 		print(JSON.stringify(result1));
# 		if(result.ok === 1 && result1.ok === 1) {
# 			print('add shards complete');
# 		}
# 	}())
# """)

addShardTemplate = (mongoConfigs) ->
	addOneShardClosure = ''
	
	for setname, setInfos of mongoConfigs.shards
		primiaryInfo = (p for p in setInfos when p.primiary is true)
		for info in primiaryInfo
			addOneShardClosure += """
				(function() {  
					var result = sh.addShard('#{setname}/#{info.host}:#{info.port}'); 
					print(JSON.stringify(result));
					resultArr.push(result);
				}());
			"""
		
	template = """
		(function(){
			var resultArr = [];
			#{addOneShardClosure}
			var err = false;
			resultArr.forEach(function(d){
				if(d.ok !== 1){
					err = true;
				}
			});
			if(err === false) {
				print('add shards complete');
			} else {
				print('add shards err happened');
			}
		}());
	"""
	return inlineTemplate(template)
	
# 增加 shards
addShards = (mongoConfigs) ->
	port = mongoConfigs.mongos.port
	new Promise (resolve) ->
		initProcess = exec "mongo --eval #{addShardTemplate(mongoConfigs)} --port #{port}", { async: true, silent: false }
		initProcess.stdout.on("data", (data) ->
			if data.match(/add shards complete/) 
				resolve(port)
				console.log "add shards complete!"
		)


# 启动多个mongo实例
target.startUpMongo = -> startMongoInstances(mongoConfigs)

# 加载mongo primiary 设置
target.addSettings = ->
	for setname, setInfos of mongoConfigs.shards
		addReplSetConfigs(setname, setInfos)
		
# 启动 mongo config server实例
target.startConfigServer = ->
	addCfgServers(mongoConfigs)

# mongos命令加载config server
target.startMongos = ->
	addCfgDBToMongos(mongoConfigs)
	
# add shards
target.addShards = ->
	addShards(mongoConfigs)

# all tasks
target.all = ->
	# start instances
	instanceObj = startMongoInstances(mongoConfigs)
	
	# add setting to primiary
	promiseAfterSet = for setname, instances of instanceObj
		do(setname) ->
			Promise.all(instances).then (data) ->
				console.log "done", setname, data
				addReplSetConfigs(setname, mongoConfigs.shards[setname])
				
	# add config servers
	cfgServerPromise = addCfgServers(mongoConfigs)
	
	# mongos config server
	mongoCfgPromise = Promise.all(cfgServerPromise).then () ->
	 	addCfgDBToMongos(mongoConfigs)
		 
	# add replsets
	Promise.all([promiseAfterSet..., mongoCfgPromise]).then ->
		setTimeout(->
			addShards(mongoConfigs)
		, 5000)
