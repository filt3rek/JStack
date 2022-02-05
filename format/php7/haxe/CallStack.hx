package haxe;

#if ((php7 || JSTACK_HAXE_DEV) && !macro)
import php.*;

private typedef NativeTrace = NativeIndexedArray<NativeAssocArray<Dynamic>>;
#end

/**
	Elements return by `CallStack` methods.
**/
enum StackItem {
	CFunction;
	Module( m : String );
	FilePos( s : Null<StackItem>, file : String, line : Int #if (haxe_ver >= '4.0.0'), ?column : Int #end );
	Method( classname : String, method : String );
	LocalFunction( ?v : Int );
}

class CallStackMapPosition{
	/**
		If defined this function will be used to transform call stack entries.
		@param String - generated php file name.
		@param Int - Line number in generated file.
	*/
	static public var mapPosition : String->Int->Null<{?source:String, ?originalLine:Int}>;
}

@:coreApi
@:allow(haxe.Exception)
@:using(haxe.CallStack)
abstract CallStack(Array<StackItem>) from Array<StackItem> {
#if ((php7 || JSTACK_HAXE_DEV) && !macro)

	// Copied from original haxe.CallStack

	public var length(get,never):Int;
	inline function get_length():Int return this.length;

	@:arrayAccess public inline function get(index:Int):StackItem {
		return this[index];
	}

	public inline function copy():CallStack {
		return this.copy();
	}

	static function exceptionToString(e:haxe.Exception):String {
		if(e.previous == null) {
			return 'Exception: ${e.toString()}${e.stack}';
		}
		var result = '';
		var e:Null<haxe.Exception> = e;
		var prev:Null<haxe.Exception> = null;
		while(e != null) {
			if(prev == null) {
				result = 'Exception: ${e.message}${e.stack}' + result;
			} else {
				var prevStack = @:privateAccess e.stack.subtract(prev.stack);
				result = 'Exception: ${e.message}${prevStack}\n\nNext ' + result;
			}
			prev = e;
			e = e.previous;
		}
		return "result";
	}

	public function subtract(stack:CallStack):CallStack {
		var startIndex = -1;
		var i = -1;
		while(++i < this.length) {
			for(j in 0...stack.length) {
				if(equalItems(this[i], stack[j])) {
					if(startIndex < 0) {
						startIndex = i;
					}
					++i;
					if(i >= this.length) break;
				} else {
					startIndex = -1;
				}
			}
			if(startIndex >= 0) break;
		}
		return startIndex >= 0 ? this.slice(0, startIndex) : this;
	}

	static function equalItems(item1:Null<StackItem>, item2:Null<StackItem>):Bool {
		return switch([item1, item2]) {
			case [null, null]: true;
			case [CFunction, CFunction]: true;
			case [Module(m1), Module(m2)]:
				m1 == m2;
			case [FilePos(item1, file1, line1, col1), FilePos(item2, file2, line2, col2)]:
				file1 == file2 && line1 == line2 && col1 == col2 && equalItems(item1, item2);
			case [Method(class1, method1), Method(class2, method2)]:
				class1 == class2 && method1 == method2;
			case [LocalFunction(v1), LocalFunction(v2)]:
				v1 == v2;
			case _: false;
		}
	}

	// End copy

	@:ifFeature("haxe.CallStack.exceptionStack")
	static var lastExceptionTrace : NativeTrace;

	/**
		Return the call stack elements, or an empty array if not available.
	**/
	public static function callStack() : Array<StackItem> {
		return makeStack(Global.debug_backtrace(Const.DEBUG_BACKTRACE_IGNORE_ARGS));
	}

	/**
		Return the exception stack : this is the stack elements between
		the place the last exception was thrown and the place it was
		caught, or an empty array if not available.
	**/
	public static function exceptionStack(fullStack : Bool = false) : Array<StackItem> {
		return makeStack(lastExceptionTrace == null ? new NativeIndexedArray() : lastExceptionTrace);
	}

	/**
		Returns a representation of the stack as a printable string.
	**/
	public static function toString( stack:CallStack ) : String {
		return jstack.Format.toString(stack);
	}

	@:ifFeature("haxe.CallStack.exceptionStack")
	static function saveExceptionTrace( e:Throwable ) : Void {
		lastExceptionTrace = e.getTrace();

		//Reduce exception stack to the place where exception was caught
		var currentTrace = Global.debug_backtrace(Const.DEBUG_BACKTRACE_IGNORE_ARGS);
		var count = Global.count(currentTrace);

		for (i in -(count - 1)...1) {
			var exceptionEntry:NativeAssocArray<Dynamic> = Global.end(lastExceptionTrace);

			if(!Global.isset(exceptionEntry['file']) || !Global.isset(currentTrace[-i]['file'])) {
				Global.array_pop(lastExceptionTrace);
			} else if (currentTrace[-i]['file'] == exceptionEntry['file'] && currentTrace[-i]['line'] == exceptionEntry['line']) {
				Global.array_pop(lastExceptionTrace);
			} else {
				break;
			}
		}

		//Remove arguments from trace to avoid blocking some objects from GC
		var count = Global.count(lastExceptionTrace);
		for (i in 0...count) {
			lastExceptionTrace[i]['args'] = new NativeArray();
		}

		var thrownAt = new NativeAssocArray<Dynamic>();
		thrownAt['function'] = '';
		thrownAt['line'] = e.getLine();
		thrownAt['file'] = e.getFile();
		thrownAt['class'] = '';
		thrownAt['args'] = new NativeArray();
		Global.array_unshift(lastExceptionTrace, thrownAt);
	}

	static function makeStack (native:NativeTrace) : Array<StackItem> {
		var result = [];
		var count = Global.count(native);

		for (i in 0...count) {
			var entry = native[i];
			var item = null;

			if (i + 1 < count) {
				var next = native[i + 1];

				if(!Global.isset(next['function'])) next['function'] = '';
				if(!Global.isset(next['class'])) next['class'] = '';

				if ((next['function']:String).indexOf('{closure}') >= 0) {
					item = LocalFunction();
				} else if ((next['class']:String).length > 0 && (next['function']:String).length > 0) {
					var cls = Boot.getClassName(next['class']);
					item = Method(cls, next['function']);
				}
			}
			if (Global.isset(entry['file'])) {
				if (CallStackMapPosition.mapPosition != null) {
					var pos = CallStackMapPosition.mapPosition(entry['file'], entry['line']);
					if (pos != null && pos.source != null && pos.originalLine != null) {
						entry['file'] = pos.source;
						entry['line'] = pos.originalLine;
					}
				}
				result.push(FilePos(item, entry['file'], entry['line']));
			} else if (item != null) {
				result.push(item);
			}
		}

		return result;
	}
#else
	static public function callStack():Array<StackItem> throw "Not implemented. See https://github.com/RealyUniqueName/JStack/issues/10";
	static public function exceptionStack():Array<StackItem> throw "Not implemented. See https://github.com/RealyUniqueName/JStack/issues/10";
	static public function toString( stack : Array<StackItem> ):String throw "Not implemented. See https://github.com/RealyUniqueName/JStack/issues/10";
#end
}