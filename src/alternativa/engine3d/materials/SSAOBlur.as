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
	public class SSAOBlur {

		private static var caches:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;
		private var programsCache:Vector.<DepthMaterialProgram>;

		public var ssaoTexture:Texture;
		public var depthTexture:Texture;

		private var quadGeometry:Geometry;

//		public var scaleX:Number = 1;
//		public var scaleY:Number = 1;
		public var width:Number = 0;
		public var height:Number = 0;

		public function SSAOBlur() {
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
				"#c0=cCenterOffset",
				"add v0, a1, c0",
				"mov o0, a0"
			], "vertexProcedure"));

			var fragmentLinker:Linker = new Linker(Context3DProgramType.FRAGMENT);

			var line:int;
			var blur:Array = [
				"#v0=vUV",
				"#s0=sDepth",
				"#s1=sSSAO",
				"#c0=cOffsets0",
				"#c1=cOffsets1",
				"#c2=cDecDepth",
				"#c3=cConstants",	// 0.0125, 1, 8
				"#c4=cWeightConst",	// 0.5, 0.75, 0.25
				// calc center color and depth
				"tex t0, v0, s0 <2d, clamp, nearest, mipnone>",
				"dp3 t0.w, t0, c2",
				"tex t0.xyz, v0, s1 <2d, clamp, nearest, mipnone>",
				// multiply by 0.0125
				"mul t3.xyz, t0.xyz, c3.x",
				"mov t3.w, c3.x"
			];
			line = blur.length;
			for (var i:int = 0; i < 4; i++) {
				// scale offset
				if ((i & 1) == 0) {
					blur[int(line++)] = "add t1, v0.xyxy, c" + i/2;
					blur[int(line++)] = "tex t2, t1.xy, s0 <2d, clamp, nearest, mipnone>";
				} else {
					blur[int(line++)] = "tex t2, t1.zw, s0 <2d, clamp, nearest, mipnone>";
				}
				// unpack depth
				blur[int(line++)] = "dp3 t2.w, t2, c2";
				// calc difference = 8*(1 - depth/center_depth)
				blur[int(line++)] = "div t2.w, t2.w, t0.w";
				blur[int(line++)] = "sub t2.w, c3.y, t2.w";
				blur[int(line++)] = "mul t2.w, t2.w, c3.z";
				// calc weight = sat(0.5 - (0.75*abs(diff) + 0.25*(diff)))
				blur[int(line++)] = "abs t2.x, t2.w";
				blur[int(line++)] = "mul t2.x, t2.x, c4.y";
				blur[int(line++)] = "mul t2.y, t2.w, c4.z";
				blur[int(line++)] = "add t2.z, t2.x, t2.y";
				blur[int(line++)] = "sub t2.w, c4.x, t2.z";
				// sample color
				blur[int(line++)] = "tex t2.xyz, t1.xy, s1 <2d, clamp, nearest, mipnone>";
				blur[int(line++)] = "mul t2.xyz, t2.xyz, t2.w";
				// calc sum
				blur[int(line++)] = "add t3, t3, t2";
			}
			// calc out color
			blur[int(line++)] = "div o0, t3.x, t3.w";

			trace(blur.join("\n"));

			var ssaoProcedure:Procedure = new Procedure(blur, "SSAOBlur");
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
			// Streams
			var positionBuffer:VertexBuffer3D = quadGeometry.getVertexBuffer(VertexAttributes.POSITION);
			var uvBuffer:VertexBuffer3D = quadGeometry.getVertexBuffer(VertexAttributes.TEXCOORDS[0]);

			var program:DepthMaterialProgram = programsCache[0];
			// Drawcall
			var drawUnit:DrawUnit = camera.renderer.createDrawUnit(null, program.program, quadGeometry._indexBuffer, 0, 2, program);
			// Streams
			drawUnit.setVertexBufferAt(program.aPosition, positionBuffer, quadGeometry._attributesOffsets[VertexAttributes.POSITION], VertexAttributes.FORMATS[VertexAttributes.POSITION]);
			drawUnit.setVertexBufferAt(program.aUV, uvBuffer, quadGeometry._attributesOffsets[VertexAttributes.TEXCOORDS[0]], VertexAttributes.FORMATS[VertexAttributes.TEXCOORDS[0]]);
			// Constants
			var dw:Number = 1/width;
			var dh:Number = 1/height;
//			var dw:Number = 0;
//			var dh:Number = 0;
			drawUnit.setVertexConstantsFromNumbers(program.cCenterOffset, dw, dh, 0, 0);
			drawUnit.setFragmentConstantsFromNumbers(program.cOffsets0, dw, -dh, -dw, -dh);
			drawUnit.setFragmentConstantsFromNumbers(program.cOffsets1, dw, dh, -dw, dh);
			drawUnit.setFragmentConstantsFromNumbers(program.cDecDepth, 1, 1/255, 0, 0);
			drawUnit.setFragmentConstantsFromNumbers(program.cConstants, 0.0125, 1, 8);
			drawUnit.setFragmentConstantsFromNumbers(program.cWeightConst, 0.5, 0.75, 0.25);
//			drawUnit.setFragmentConstantsFromNumbers(program.cWeightConst, 0.5, 0, 0);
			drawUnit.setTextureAt(program.sDepth, depthTexture);
			drawUnit.setTextureAt(program.sSSAO, ssaoTexture);
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
	public var cCenterOffset:int = -1;
	public var cOffsets0:int = -1;
	public var cOffsets1:int = -1;
	public var cDecDepth:int = -1;
	public var cConstants:int = -1;
	public var cWeightConst:int = -1;
	public var sDepth:int = -1;
	public var sSSAO:int = -1;

	public function DepthMaterialProgram(vertex:Linker, fragment:Linker) {
		super(vertex, fragment);
	}

	override public function upload(context3D:Context3D):void {
		super.upload(context3D);

		aPosition =  vertexShader.findVariable("aPosition");
		aUV =  vertexShader.findVariable("aUV");
		cCenterOffset = vertexShader.findVariable("cCenterOffset");
		cOffsets0 = fragmentShader.findVariable("cOffsets0");
		cOffsets1 = fragmentShader.findVariable("cOffsets1");
		cDecDepth = fragmentShader.findVariable("cDecDepth");
		cConstants = fragmentShader.findVariable("cConstants");
		cWeightConst = fragmentShader.findVariable("cWeightConst");
		sDepth = fragmentShader.findVariable("sDepth");
		sSSAO = fragmentShader.findVariable("sSSAO");
	}

}
