import haxe.crypto.Base64;

/** HTML media playback routed to the platform decoder and audio output device. */
class WebAudio extends JsObject {
	static var proto:JsObject;
	static final active:Array<WebAudio> = [];

	final events:WebEvents;
	var source = "";
	var handle = 0;
	var generation = 0;
	var ready = 0;
	var playing = false;
	var paused = true;
	var ended = false;
	var loop = false;
	var muted = false;
	var volume = 1.;
	var duration = Math.NaN;
	var position = 0.;
	var loading = false;
	var waiting:Array<JsPromise> = [];

	public static function install() {
		if (!DesktopServices.available())
			return;
		final ctor = Js.fn((_, a) -> {
			final audio = new WebAudio();
			if (Js.at(a, 0) != Js.u)
				Js.put(audio, "src", a[0]);
			return audio;
		}, true);
		proto = ctor.read("prototype");
		Js.realm.define("Audio", ctor);
		Js.realm.define("HTMLAudioElement", ctor);
	}

	public function new() {
		super(proto);
		events = new WebEvents(this);
		getters.set("src", () -> source);
		getters.set("currentSrc", () -> source);
		setters.set("src", v -> {
			dispose();
			source = Js.str(v);
			if (source != "")
				load();
		});
		getters.set("readyState", () -> ready);
		getters.set("paused", () -> paused);
		getters.set("ended", () -> ended);
		getters.set("duration", () -> duration);
		getters.set("currentTime", () -> handle == 0 ? position : (cast native("state") : Array<Dynamic>)[0]);
		setters.set("currentTime", v -> {
			final n = Js.num(v);
			if (!Math.isFinite(n))
				throw "TypeError: invalid playback position";
			position = Math.max(0, n);
			if (handle != 0)
				native("seek", position);
			ended = false;
		});
		getters.set("volume", () -> volume);
		setters.set("volume", v -> {
			final n = Js.num(v);
			if (!Math.isFinite(n) || n < 0 || n > 1)
				throw "IndexSizeError";
			volume = n;
			updateVolume();
		});
		getters.set("muted", () -> muted);
		setters.set("muted", v -> {
			muted = Js.truth(v);
			updateVolume();
		});
		getters.set("loop", () -> loop);
		setters.set("loop", v -> {
			loop = Js.truth(v);
			if (handle != 0)
				native("loop", loop);
		});
		define("canPlayType", Js.fn((_, a) -> {
			final s = Js.str(Js.at(a, 0)).toLowerCase().split(";")[0];
			return [
				"audio/wav",
				"audio/wave",
				"audio/x-wav",
				"audio/mpeg",
				"audio/mp4",
				"audio/aac",
				"audio/x-aiff"
			].contains(s) ? "probably" : "";
		}, false));
		define("play", Js.fn((_, _) -> {
			final p = new JsPromise();
			waiting.push(p);
			paused = false;
			if (handle != 0)
				start();
			else if (source == "")
				failure("NotSupportedError");
			else if (!loading)
				load();
			return p;
		}, false));
		define("pause", Js.fn((_, _) -> {
			if (handle != 0)
				native("pause");
			final changed = !paused;
			playing = false;
			paused = true;
			active.remove(this);
			for (p in waiting)
				p.reject("AbortError");
			waiting = [];
			if (changed)
				events.fire("pause");
			return Js.u;
		}, false));
		define("load", Js.fn((_, _) -> {
			dispose();
			if (source != "")
				load();
			return Js.u;
		}, false));
		define("cloneNode", Js.fn((_, _) -> {
			final a = new WebAudio();
			Js.put(a, "src", source);
			return a;
		}, false));
	}

	function native(op:String, ?v:Dynamic):Dynamic
		return DesktopServices.call("audio." + op, v == null ? [handle] : [handle, v]);

	function updateVolume() {
		if (handle != 0)
			native("volume", muted ? 0. : volume);
	}

	function dispose() {
		generation++;
		active.remove(this);
		if (handle != 0)
			native("dispose");
		handle = 0;
		ready = 0;
		playing = false;
		loading = false;
		paused = true;
		ended = false;
		position = 0;
		duration = Math.NaN;
		for (p in waiting)
			p.reject("AbortError");
		waiting = [];
	}

	function failure(message:String) {
		loading = false;
		paused = true;
		for (p in waiting)
			p.reject(message);
		waiting = [];
		define("error", message);
		events.fire("error");
	}

	function load() {
		final id = ++generation;
		loading = true;
		WebNetwork.load(source, b -> {
			if (id != generation)
				return;
			var result:Array<Dynamic>;
			try
				result = DesktopServices.call("audio.load", [Base64.encode(b.bytes)])
			catch (e:Dynamic) {
				failure(Std.string(e));
				return;
			}
			handle = result[0];
			duration = result[1];
			loading = false;
			ready = 4;
			updateVolume();
			native("loop", loop);
			if (position != 0)
				native("seek", position);
			for (e in ["loadedmetadata", "loadeddata", "canplay", "canplaythrough"])
				events.fire(e);
			if (!paused || Js.truth(read("autoplay")))
				start();
		}, e -> {
			if (id == generation)
				failure(e);
		});
	}

	function start() {
		if (!playing) {
			if (ended)
				native("seek", 0.);
			if (native("play") != true) {
				failure("Audio output failed");
				return;
			}
			ended = false;
			playing = true;
			paused = false;
			active.push(this);
			events.fire("play");
			events.fire("playing");
		}
		for (p in waiting)
			p.resolve(Js.u);
		waiting = [];
	}

	public static function poll() {
		for (audio in active.copy()) {
			final state:Array<Dynamic> = audio.native("state");
			audio.position = state[0];
			if (state[1] == false && audio.playing) {
				audio.playing = false;
				audio.paused = true;
				audio.ended = true;
				audio.position = audio.duration;
				active.remove(audio);
				audio.events.fire("timeupdate");
				audio.events.fire("ended");
			}
		}
	}
}
