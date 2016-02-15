package h3d.prim;

/**
	Vertex buffers are limited to 65K vertexes because of the 16-bits limitation of the index buffers.
	BigPrimitive allows you to easily create large buffers by spliting the buffers.
**/
class BigPrimitive extends Primitive {

	var isRaw : Bool;
	var stride : Int;
	var buffers : Array<Buffer>;
	var allIndexes : Array<Indexes>;
	var tmpBuf : hxd.FloatBuffer;
	var tmpIdx : hxd.IndexBuffer;
	var bounds : h3d.col.Bounds;
	var bufPos : Int;
	var idxPos : Int;
	var startIndex : Int;
	#if debug
	var allocPos : h3d.impl.AllocPos;
	#end

	static var PREV_BUFFER : hxd.FloatBuffer;
	static var PREV_INDEX : hxd.IndexBuffer;

	public function new(stride, isRaw=false, ?pos : h3d.impl.AllocPos ) {
		this.isRaw = isRaw;
		buffers = [];
		allIndexes = [];
		bounds = new h3d.col.Bounds();
		this.stride = stride;
		if( stride < 3 ) throw "Minimum stride = 3";
		#if debug
		allocPos = pos;
		#end
	}

	/**
		Call begin() before starting to add vertexes/indexes to the primitive.
		The count value is the number of vertexes you will add, it will automatically flush() if it doesn't fit into the current buffer.
	**/
	public function begin(count) {
		startIndex = Std.int(bufPos / stride);
		if( startIndex + count >= 65535 ) {
			if( count >= 65535 ) throw "Too many vertices in begin()";
			flush();
		}
		if( tmpBuf == null ) {
			tmpBuf = PREV_BUFFER;
			if( tmpBuf == null )
				tmpBuf = new hxd.FloatBuffer();
			else
				PREV_BUFFER = null;
			tmpBuf.grow(65535 * stride);
		}
		if( tmpIdx == null ) {
			tmpIdx = PREV_INDEX;
			if( tmpIdx == null )
				tmpIdx = new hxd.IndexBuffer();
			else
				PREV_INDEX = null;
		}
	}

	/**
		This is similar to addVertexValue for X Y and Z, but will also update the bounds if you wish to have them calculated.
	**/
	public inline function addPoint(x, y, z) {
		tmpBuf[bufPos++] = x;
		tmpBuf[bufPos++] = y;
		tmpBuf[bufPos++] = z;
		bounds.addPos(x, y, z);
	}

	public inline function addBounds(x, y, z) {
		bounds.addPos(x, y, z);
	}

	public inline function addVertexValue(v) {
		tmpBuf[bufPos++] = v;
	}

	public inline function addIndex(i) {
		tmpIdx[idxPos++] = i + startIndex;
	}

	override function triCount() {
		var count = 0;
		for( i in allIndexes )
			count += i.count;
		count += idxPos;
		return Std.int(count/3);
	}

	override function vertexCount() {
		var count = 0;
		for( b in buffers )
			count += b.vertices;
		count += Std.int(bufPos / stride);
		return count;
	}

	static var TOTAL = 0;

	/**
		Flush the current buffer.
		It is required to call begin() after a flush()
	**/
	public function flush() {
		if( tmpBuf != null ) {
			if( bufPos > 0 && idxPos > 0 ) {
				var b = h3d.Buffer.ofSubFloats(tmpBuf, stride, Std.int(bufPos/stride) #if debug ,null,allocPos #end);
				if( isRaw ) b.flags.set(RawFormat);
				buffers.push(b);
				allIndexes.push(h3d.Indexes.alloc(tmpIdx, 0, idxPos));
			}
			if( PREV_BUFFER == null || PREV_BUFFER.length < tmpBuf.length )
				PREV_BUFFER = tmpBuf;
			if( PREV_INDEX == null || PREV_INDEX.length < tmpIdx.length )
				PREV_INDEX = tmpIdx;
			tmpBuf = null;
			tmpIdx = null;
			bufPos = 0;
			idxPos = 0;
			startIndex = 0;
		}
	}

	override function render( engine : h3d.Engine ) {
		if( tmpBuf != null ) flush();
		for( i in 0...buffers.length )
			engine.renderIndexed(buffers[i],allIndexes[i]);
	}

	override function getBounds() {
		return bounds;
	}

	override function dispose() {
		clear();
	}

	public function clear() {
		bounds.empty();
		for( b in buffers )
			b.dispose();
		for( i in allIndexes )
			i.dispose();
		buffers = [];
		allIndexes = [];
		bufPos = 0;
		tmpBuf = null;
		tmpIdx = null;
	}

	/**
		Adds a complete object to the primitive, with custom position,scale,rotation.
		See addSub for complete documentation.
	**/
	public function add( buf : hxd.FloatBuffer, idx : hxd.IndexBuffer, dx : Float = 0. , dy : Float = 0., dz : Float = 0., rotation = 0., scale = 1., stride = -1 ) {
		return addSub(buf, idx, 0, 0, Std.int(buf.length / (stride < 0 ? this.stride : stride)), Std.int(idx.length / 3), dx, dy, dz, rotation, scale, stride);
	}
	/**
		Adds a buffer to the primitive, with custom position,scale,rotation.
		The buffer can have more stride than the BigPrimitive, but not less.
		It is assumed that the buffer contains [X,Y,Z,NX,NY,NZ,U,V,R,G,B] (depending on his stride) so the different offsets are applied to the corresponding components.
		However if the stride is 5, we assume [X,Y,Z,U,V]
	**/
	@:noDebug
	public function addSub( buf : hxd.FloatBuffer, idx : hxd.IndexBuffer, startVert, startTri, nvert, triCount, dx : Float = 0. , dy : Float = 0., dz : Float = 0., rotation = 0., scale = 1., stride = -1, deltaU = 0., deltaV = 0., color = 1. ) {
		if( stride < 0 ) stride = this.stride;
		if( stride < this.stride ) throw "only stride >= " + this.stride+" allowed";
		begin(nvert);
		var start = startIndex;
		var cr = Math.cos(rotation);
		var sr = Math.sin(rotation);
		var pos = bufPos;
		var tmpBuf = tmpBuf;
		for( i in 0...nvert ) {
			var p = (i + startVert) * stride;
			var x = buf[p++];
			var y = buf[p++];
			var z = buf[p++];
			var tx = (x * cr - y * sr) * scale;
			var ty = (x * sr + y * cr) * scale;

			inline function add(v) tmpBuf[pos++] = v;

			var vx = dx + tx;
			var vy = dy + ty;
			var vz = dz + z * scale;
			add(vx);
			add(vy);
			add(vz);
			bounds.addPos(vx, vy, vz);

			switch( this.stride ) {
			case 3:
				continue;
			case 4:
				add(buf[p++]);
			case 5:
				// assume no normal
				add(buf[p++] + deltaU);
				add(buf[p++] + deltaV);
			case 6:
				var nx = buf[p++];
				var ny = buf[p++];
				var nz = buf[p++];
				var tnx = nx * cr - ny * sr;
				var tny = nx * sr + ny * cr;
				add(tnx);
				add(tny);
				add(nz);
			case 7:
				var nx = buf[p++];
				var ny = buf[p++];
				var nz = buf[p++];
				var tnx = nx * cr - ny * sr;
				var tny = nx * sr + ny * cr;
				add(tnx);
				add(tny);
				add(nz);
				add(buf[p++] + deltaU);
			case 8, 9, 10:
				var nx = buf[p++];
				var ny = buf[p++];
				var nz = buf[p++];
				var tnx = nx * cr - ny * sr;
				var tny = nx * sr + ny * cr;
				add(tnx);
				add(tny);
				add(nz);

				// UV
				add(buf[p++] + deltaU);
				add(buf[p++] + deltaV);

				for( i in 8...this.stride )
					add(buf[p++]);

			default:
				var nx = buf[p++];
				var ny = buf[p++];
				var nz = buf[p++];
				var tnx = nx * cr - ny * sr;
				var tny = nx * sr + ny * cr;
				add(tnx);
				add(tny);
				add(nz);

				// UV
				add(buf[p++] + deltaU);
				add(buf[p++] + deltaV);

				// COLOR
				add(buf[p++] * color);
				add(buf[p++] * color);
				add(buf[p++] * color);

				for( i in 11...this.stride )
					add(buf[p++]);
			}
		}
		bufPos = pos;
		start -= startVert;
		for( i in 0...triCount * 3 )
			tmpIdx[idxPos++] = idx[i+startTri*3] + start;
	}

}