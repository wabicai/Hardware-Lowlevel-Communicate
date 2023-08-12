import HardwareSDK from '@onekeyfe/hd-common-connect-sdk'

const UI_EVENT = 'UI_EVENT';
const UI_REQUEST = {
  REQUEST_PIN: 'ui-request_pin',
	REQUEST_PASSPHRASE: 'ui-request_passphrase',
  REQUEST_PASSPHRASE_ON_DEVICE: 'ui-request_passphrase_on_device',
	REQUEST_BUTTON: 'ui-button',
}
const UI_RESPONSE = {
  RECEIVE_PIN: 'ui-receive_pin',
  RECEIVE_PASSPHRASE: 'ui-receive_passphrase',
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
	registerBridgeHandler(_bridge)
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
			listenHardwareEvent(HardwareSDK)
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
					resolve(response)
				})
			})
		},
		receive: () => {
			return new Promise((resolve) => {
				bridge.callHandler('receive', {}, (response) => {
					resolve(response)
				})
			})
		},
		connect: (uuid) => {
			return new Promise((resolve) => {
				bridge.callHandler('connect', {uuid})
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

function listenHardwareEvent(SDK) {
	SDK.on(UI_EVENT, (message) => {
		if (message.type === UI_REQUEST.REQUEST_PIN) {
			// enter pin code on the device
			SDK.uiResponse({
				type: UI_RESPONSE.RECEIVE_PIN,
				payload: '@@ONEKEY_INPUT_PIN_IN_DEVICE',
			});	
		}
		if (message.type === UI_REQUEST.REQUEST_PASSPHRASE) {
			// enter passphrase on the device
			SDK.uiResponse({
				type: UI_RESPONSE.RECEIVE_PASSPHRASE,
				payload: {
					value: '',
					passphraseOnDevice: true,
					save: false,
				},
			});
		}
		if (message.type === UI_REQUEST.REQUEST_BUTTON) {
			console.log('request button, should show dialog on client')
		}
	})
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

	bridge.registerHandler('btcGetAddress', async (data, callback) => {
		try {
			const SDK = await getHardwareSDKInstance()
			const { connectId, deviceId, path, coin, showOnOneKey } = data
			// 该方法只需要钱包开启 passphrase 时调用，如果钱包未启用 passphrase，不需要调用该方法，以便减少与硬件的交互次数，提高用户体验
			// passphraseState 理论上应该由 native 传入，创建完一个隐藏钱包后客户端对 passphraseState 进行缓存
			const passphraseStateRes = await SDK.getPassphraseState(connectId);

			const params = {
				path,
				coin,
				showOnOneKey,
			}
			// 如果用户打开 passphrase ，则需要传入参数 passphraseState
			passphraseStateRes.payload && (params['passphraseState'] = passphraseStateRes.payload)
			const response = await SDK.btcGetAddress(connectId, deviceId, params)
			callback(response)
		} catch (e) {
			console.error(e)
			callback({success: false, error: e.message})
		}
	})
}
