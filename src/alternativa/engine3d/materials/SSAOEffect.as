package alternativa.engine3d.materials {

	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.core.DrawUnit;
	import alternativa.engine3d.core.Renderer;
	import alternativa.engine3d.core.VertexAttributes;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	import alternativa.engine3d.resources.Geometry;

	import flash.display3D.Context3D;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.VertexBuffer3D;
	import flash.display3D.textures.Texture;
	import flash.utils.Dictionary;

	use namespace alternativa3d;
	public class SSAOEffect {

		private static var caches:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;
		private var programsCache:Vector.<DepthMaterialProgram>;

		public var depthTexture:Texture;

		private var quadGeometry:Geometry;

		public var scaleX:Number = 1;
		public var scaleY:Number = 1;

		public function SSAOEffect() {
			quadGeometry = new Geometry();
			quadGeometry.addVertexStream([VertexAttributes.POSITION, VertexAttributes.POSITION, VertexAttributes.POSITION, VertexAttributes.TEXCOORDS[0], VertexAttributes.TEXCOORDS[0]]);
			quadGeometry.numVertices = 4;
			quadGeometry.setAttributeValues(VertexAttributes.POSITION, Vector.<Number>([-1, 1, 0, 1, 1, 0, 1, -1, 0, -1, -1, 0]));
			//quadGeometry.setAttributeValues(VertexAttributes.POSITION, Vector.<Number>([0, 0, 0, 1, 0, 0, 1, -1, 0, 0, -1, 0]));
			quadGeometry.setAttributeValues(VertexAttributes.TEXCOORDS[0], Vector.<Number>([0, 0, 1, 0, 1, 1, 0, 1]));
			quadGeometry._indices = Vector.<uint>([0, 3, 2, 0, 2, 1]);
		}

		private function setupProgram():DepthMaterialProgram {
			// project vector in camera
			var vertexLinker:Linker = new Linker(Context3DProgramType.VERTEX);
			vertexLinker.addProcedure(new Procedure([
				"#a0=aPosition",
				"#a1=aUV",
				"#v0=vUV",
				"#c0=cScale",
				"mul v0, a1, c0",
				"mov o0, a0"
			], "vertexProcedure"));

			var fragmentLinker:Linker = new Linker(Context3DProgramType.FRAGMENT);

			// Sample center depth
			// Sample neighbours depth nearest to our coordinate (delta)
			// Compare center depth with each neighbour
			// sample_vis = 1 - sat((center_depth - depth)/distance)
			// result = sum(vis0, vis1, ...)/num_samples

			var ssaoProcedure:Procedure = new Procedure([
				"#v0=vUV",
				"#c0=cConstants",	// decode const
				"#c1=cOffset",		// 0.5, 0,
				"#c2=cCoeff",		// distance, num_sampes, 1
				"#s0=sDepth",
				// unpack depth
				"tex t0, v0, s0 <2d, clamp, nearest, mipnone>",
				"dp3 t0.w, t0, c0",
				// sample neighbours
				"add t1.xy, v0.xy, c1.xy",
				"tex t0.xy, t1.xy, s0 <2d, clamp, nearest, mipnone>",
				"dp3 t0.x, t0, c0",
				// check visibility
				"sub t1.z, t0.w, t0.x",
				"mul t1.z, t1.z, c2.x",	// 10000/distance
				"sat t1.z, t1.z",
				"sub t1.w, c2.z, t1.z",
				// -offset
				"sub t1.xy, v0.xy, c1.xy",
				"tex t0.xy, t1.xy, s0 <2d, clamp, nearest, mipnone>",
				"dp3 t0.x, t0, c0",
				// check visibility
				"sub t1.z, t0.w, t0.x",
				"mul t1.z, t1.z, c2.x",	// 10000/distance
				"sat t1.z, t1.z",
				"sub t1.z, c2.z, t1.z",
				"add t1.w, t1.w, t1.z",
				"div t1.w, t1.w, c2.y",
				"mov o0, t1.w"
			]);
			fragmentLinker.addProcedure(ssaoProcedure);

			fragmentLinker.varyings = vertexLinker.varyings;
			return new DepthMaterialProgram(vertexLinker, fragmentLinker);
		}

		public function collectQuadDraw(camera:Camera3D):void {
			// Check validity
			if (depthTexture == null) return;

			// Renew program cache for this context
			if (camera.context3D != cachedContext3D) {
				cachedContext3D = camera.context3D;
				programsCache = caches[cachedContext3D];
				quadGeometry.upload(camera.context3D);
				if (programsCache == null) {
					programsCache = new Vector.<DepthMaterialProgram>(1);
					programsCache[0] = setupProgram();
					programsCache[0].upload(camera.context3D);
					caches[cachedContext3D] = programsCache;
				}
			}
			// Strams
			var positionBuffer:VertexBuffer3D = quadGeometry.getVertexBuffer(VertexAttributes.POSITION);
			var uvBuffer:VertexBuffer3D = quadGeometry.getVertexBuffer(VertexAttributes.TEXCOORDS[0]);

			var program:DepthMaterialProgram = programsCache[0];
			// Drawcall
			var drawUnit:DrawUnit = camera.renderer.createDrawUnit(null, program.program, quadGeometry._indexBuffer, 0, 2, program);
			// Streams
			drawUnit.setVertexBufferAt(program.aPosition, positionBuffer, quadGeometry._attributesOffsets[VertexAttributes.POSITION], VertexAttributes.FORMATS[VertexAttributes.POSITION]);
			drawUnit.setVertexBufferAt(program.aUV, uvBuffer, quadGeometry._attributesOffsets[VertexAttributes.TEXCOORDS[0]], VertexAttributes.FORMATS[VertexAttributes.TEXCOORDS[0]]);
			// Constants
			drawUnit.setVertexConstantsFromNumbers(program.cScale, scaleX, scaleY, 0);
			drawUnit.setFragmentConstantsFromNumbers(program.cConstants, 1, 1/255, 0, 0);
			drawUnit.setFragmentConstantsFromNumbers(program.cOffset, 0, 0.01, 0, 0);

			var distance:Number = 10/(camera.farClipping - camera.nearClipping);
			drawUnit.setFragmentConstantsFromNumbers(program.cCoeff, 10000/distance, 2, 1);
			drawUnit.setTextureAt(program.sDepth, depthTexture);
			// Send to render
			camera.renderer.addDrawUnit(drawUnit, Renderer.OPAQUE);
		}

	}
}

import alternativa.engine3d.materials.ShaderProgram;
import alternativa.engine3d.materials.compiler.Linker;

import flash.display3D.Context3D;

class DepthMaterialProgram extends ShaderProgram {

	public var aPosition:int = -1;
	public var aUV:int = -1;
	public var cScale:int = -1;
	public var cConstants:int = -1;
	public var cOffset:int = -1;
	public var cCoeff:int = -1;
	public var sDepth:int = -1;

	public function DepthMaterialProgram(vertex:Linker, fragment:Linker) {
		super(vertex, fragment);
	}

	override public function upload(context3D:Context3D):void {
		super.upload(context3D);

		aPosition =  vertexShader.findVariable("aPosition");
		aUV =  vertexShader.findVariable("aUV");
		cScale = vertexShader.findVariable("cScale");
		cConstants = fragmentShader.findVariable("cConstants");
		cOffset = fragmentShader.findVariable("cOffset");
		cCoeff = fragmentShader.findVariable("cCoeff");
		sDepth = fragmentShader.findVariable("sDepth");
	}

}
