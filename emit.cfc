/*
Copyright 2014 Ryan Guill

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

========================================================================================================================

See documentation at https://github.com/ryanguill/emit
*/

component {

	//intentionally don't use an init method so that subclasses do not have to call super.init()

	private function _ensurePrivateVariables () {
		if (!structKeyExists(variables, "_emit")) {
			variables._emit = {};
			_emit.listeners = createObject("java", "java.util.LinkedHashMap").init();
			_emit.maxListeners = 10;
			_emit.caseSensitiveEventName = true;
		}
	}

	private function _normalizeEventName (required string event) {
		_ensurePrivateVariables();
		if (!_emit.caseSensitiveEventName) {
			return ucase(event);
		}
		return event;
	}

	function setMaxListeners (required numeric n) {
		_ensurePrivateVariables();
		_emit.maxListeners = n;
	}

	function getMaxListeners () {
		_ensurePrivateVariables();
		return _emit.maxListeners;
	}

	function setCaseSensitiveEventName (required boolean value) {
		_ensurePrivateVariables();
		_emit.caseSensitiveEventName = value;
	}

	function isCaseSensitiveEventName () {
		_ensurePrivateVariables();
		return _emit.caseSensitiveEventName;
	}

	function addEventListener (required string event, required any listener, boolean async = false, boolean once = false) {
		_ensurePrivateVariables();

		event = _normalizeEventName(event);

		if (!structKeyExists(_emit.listeners, event)) {
			_emit.listeners[event] = [];
		}

		if (arrayLen(_emit.listeners[event]) > getMaxListeners()) {
			throw(type="Emit.maxListenersExceeded", message="Max Listeners exceeded for event: " & event, detail="Current Max Listeners value: " & getMaxListeners);
		}

		arrayAppend(_emit.listeners[event], {listener=listener, async=async, once=once});

		emit("newListener", listener);

		return this;
	}

	function on (required string event, required any listener, boolean async = false) {
		return addEventListener(argumentCollection=arguments);
	}

	function once (required string event, required any listener, boolean async = false) {
		_ensurePrivateVariables();
		addEventListener(event, listener, async, true);
	}

	function removeListener (required string event, required any listener) {
		_ensurePrivateVariables();

		event = _normalizeEventName(event);

		if (structKeyExists(_emit.listeners, event)){
			var listeners = _emit.listeners[event];

			for (var i = 1; i <= arrayLen(listeners); i++) {
				if (listener.equals(listeners[i].listener)) {
					arrayDeleteAt(listeners, i);
					emit("removeListener", listener.listener);
					break;
				}
			}
		}

		return this;
	}

	function removeAllListeners (required string event) {
		_ensurePrivateVariables();

		event = _normalizeEventName(event);

		//todo: check to see if reinitializing the array is faster than clearing it
		if (structKeyExists(_emit.listeners, event)){
			arrayClear(_emit.listeners[event]);
		}

		return this;
	}

	function listeners (required string event) {
		_ensurePrivateVariables();

		event = _normalizeEventName(event);

		if (!structKeyExists(_emit.listeners, event)) {
			return [];
		}

		return duplicate(_emit.listeners[event]);
	}

	function emit(required string event) {
		_ensurePrivateVariables();

		event = _normalizeEventName(event);

		var localEvent = event;

		if (!structKeyExists(_emit.listeners, event)) {
			return false;
		}

		var listeners = _emit.listeners[event];

		if (!arrayLen(listeners)) {
			return false;
		}

		structDelete(arguments, "event");

		for (var listener in listeners) {

			if (isStruct(listener.listener)) {
				//this is a pipeline
				listener.listener.run(argumentCollection=arguments);
			} else {
				//this is a regular listener
				if (listener.async) {
					arguments.f = listener.listener;
					async(argumentCollection=arguments);
					
				} else {
					try {
						listener.listener(argumentCollection=arguments);
					} catch (any e) {
						arguments.exception = e;
						dispatchError(argumentCollection=arguments);
					}
				}
			}

			if (listener.once) {
				emit.removeListener(localEvent, listener.listener);
			}

		}

		return true;
	}

	function dispatch (required string event) {
		return emit(argumentCollection=arguments);
	}

	function async (required any f) {
		var listener = f;
		structDelete(arguments, "f");

		thread action="run" name="thread_#createUUID()#" listener=listener args=arguments emit=this {
			try {
				listener(argumentCollection=arguments);
			} catch (any e) {
				arguments.exception = e;
				emit.dispatchError(argumentCollection=arguments);
			}
		}

		//writedump("done");
	}

	function pipeline (required string event, boolean async = false, boolean once = false) {
		var q = [];
		var isComplete = false;

		var callAsync = variables.async;
		
		var o = {
			then = function(required any f) {
				arrayAppend(q, f);
				return o;
			},
			complete = function() {
				isComplete = true;
				addEventListener(event, o, async, once);
				return o;
			},
			run = function() {
				if (!isComplete) {
					throw(type="Emit.pipelineNotComplete", message="You must call complete() on the pipeline when you are done adding listeners");
				}
				var args = arguments;
				for (var f in q) {
					if (async) {
						callAsync(function() {
							f(argumentCollection=args);
						});
					} else {
						f(argumentCollection=args);
					}
				}
			}
		};

		return o;
	}



	function dispatchError () {
		if (structKeyExists(_emit.listeners, "error") && arrayLen(_emit.listeners["error"])) {
			arguments.event = "error";
			return emit(argumentCollection=arguments);
		}

		if (structKeyExists(arguments, "exception")) {
			throw(arguments.exception);
		} else if (structKeyExists(arguments, "message")) {
			throw(message=message);
		} else {
			throw(type="Emit.unknownException", message="Unhandled Exception");
		}

	}

	/*
		abandoning this for the moment - it requires you to refer to methods as variables.method() inside of the monkeypatched object, which isnt ideal.  Not sure if there is a better way or not

		function makeEmitter (required target) {
			//check to make sure that the target doesnt already have any of the functions we want to add
			var functionsToAdd = ["_ensurePrivateVariables","addEventListener","on","once","removeListener","removeAllListeners","setMaxListeners","getMaxListeners","listeners","emit","dispatch","dispatchError"];

			var f = {};

			for (f in getMetadata(target).functions) {
				if (arrayFindNoCase(functionsToAdd, f.name)) {
					throw(type="Emit.duplicateFunctionDefinition", message="Error making target an event Emitter, target already defines method: " & f.name);
				}
			}

			//monkeypatch
			//cant make ensurePrivateVariables private unfortunately
			for (f in functionsToAdd) {
				target[f] = variables[f];
			}

			return target;
		}
	*/



}