import HardwareSDK from '@onekeyfe/hd-common-connect-sdk'

function checkSDK() {
	console.log('===> hello world: ', HardwareSDK)
	console.log(HardwareSDK)
}

let bridge

function setupWKWebViewJavascriptBridge(callback) {
	if (window.WKWebViewJavascriptBridge) {
		return callback(WKWebViewJavascriptBridge);
	}
	if (window.WKWVJBCallbacks) {
		return window.WKWVJBCallbacks.push(callback);
	}
	window.WKWVJBCallbacks = [callback];
	window.webkit.messageHandlers.iOS_Native_InjectJavascript.postMessage(null)
}

setupWKWebViewJavascriptBridge(function (_bridge) {
	bridge = _bridge
	/* Initialize your app here */
	registerBridgeHandler(_bridge)

	bridge.registerHandler('testJavascriptHandler', function (data, responseCallback) {
		console.log('iOS called testJavascriptHandler with', data)
		responseCallback({
			'Javascript Says': 'Right back atcha!'
		})
	})
})

let isInitialized = false
function getHardwareSDKInstance() {
	return new Promise(async (resolve, reject) => {
		if (!bridge) {
			throw new Error('bridge is not connected')
		}
		if (isInitialized) {
			console.log('already initialized, skip')
			resolve(HardwareSDK)
			return
		}
	
		const settings = {
			env: 'lowlevel',
			debug: true 
		}
	
		const plugin = createLowlevelPlugin()
	
		try {
			await HardwareSDK.init(settings, undefined, plugin)
			console.log('HardwareSDK init success')
			isInitialized = true
			resolve(HardwareSDK)

			// HardwareSDK.on("LOG_EVENT", (messages) => {
			// 	if (messages && Array.isArray(messages.payload)) {
			// 		console.log(messages.payload.join(' '));
			// 	}
			// });
		} catch (e) {
			reject(e)
		}
	})
}

function createLowlevelPlugin() {
	const plugin = {
		enumerate: () => {
			return new Promise((resolve) => {
				bridge.callHandler('enumerate', {}, (response) => {
					console.log('===> call enumerate response: ', response)
					resolve(response)
				})
			})
		},
		send: (uuid, data) => {
			return new Promise((resolve) => {
				bridge.callHandler('send', {uuid, data}, (response) => {
					console.log('call send response: ', response)
					resolve(response)
				})
			})
		},
		receive: () => {
			return new Promise((resolve) => {
				bridge.callHandler('receive', {}, (response) => {
					console.log('call receive response: ', response)
					resolve(response)
				})
			})
		},
		connect: (uuid) => {
			return new Promise((resolve) => {
				bridge.callHandler('connect', {uuid}, (response) => {
					console.log('call pre connect response: ', response)
				})
				bridge.registerHandler('connectFinished', () => {
					resolve()
				})
			})
		},
		disconnect: (uuid)  => {
			return new Promise((resolve) => {
				bridge.callHandler('disconnect', {uuid}, (response) => {
					console.log('call connect response: ', response)
					resolve(response)
				})
			})
		},

		init: () => {
			console.log('call init')
			return Promise.resolve()
		},

		version: 'OneKey-1.0'
	}

	return plugin
}

function registerBridgeHandler(bridge) {
	bridge.registerHandler('init', async (data, callback) => {
		try {
			await getHardwareSDKInstance()
			callback({success: true})
		} catch (e) {
			console.error(e)
			callback({success: false, error: e.message})
		}
	})

	bridge.registerHandler('searchDevice', async (data, callback) => {
		try {
			const SDK = await getHardwareSDKInstance()
			const response = await SDK.searchDevices()
			callback(response)
		} catch (e) {
			console.error(e)
			callback({success: false, error: e.message})
		}	
	})

	bridge.registerHandler('getFeatures', async (data, callback) => {
		try {
			const SDK = await getHardwareSDKInstance()
			const response = await SDK.getFeatures(data.connectId)
			callback(response)
		} catch (e) {
			console.error(e)
			callback({success: false, error: e.message})
		}
	})
}
