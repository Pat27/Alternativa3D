/**
 * Created with IntelliJ IDEA.
 * User: gaev
 * Date: 25.06.12
 * Time: 20:06
 * To change this template use File | Settings | File Templates.
 */
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

	public class SSAOVolumetric {

		private static var caches:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;
		private var programsCache:Vector.<DepthMaterialProgram>;

		public var depthTexture:Texture;

		private var quadGeometry:Geometry;

		public var scaleX:Number = 1;
		public var scaleY:Number = 1;

		public var width:int = 1024;
		public var height:int = 1024;
		public var offset:int = 3;
		public var bias:Number = -0.1;
		public var multiplier:Number = 0.7;
		public var maxR:Number = 0.5;

		public function SSAOVolumetric() {
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
				"#c1=cOffset",		// offset/width, offset/height, -offset/width, -offset/height
				"#c2=cCoeff",		// maxR, multiplier, 1/9, 1
				"#s0=sDepth",
				// unpack depth
				// v0 - current point
				// t0 - texture value
				// t1 - coordinates

				// t2.x - P depth
				// t2.y - B depth
				// t2.z - C (Current point depth)
				// c2.x - l (= P - B)

				// t3.x = C - B
				// t3.w - sum

				"mov t1.x, c2.w",
				"sub t1, t1.x, t1.x",
				"mov t3.w, t1.x",

				// 0 segment
				// -------------
				"tex t0, v0, s0 <2d, clamp, nearest, mipnone>",
				"dp3 t2.x, t0.xyz, c0.xyz",								// decode value
				// -------------
				"sub t2.y, t2.x, c2.x",									// calculate B\
				"mov t4, c1",
//				"div t4.x, c1.x, t2.x",									// calculate Offsets
//				"div t4.y, c1.y, t2.x",
//				"div t4.z, c1.z, t2.x",
//				"div t4.w, c1.w, t2.x",

				// 1 segment
				"add t1.x, v0.x, t4.x",									// calculate coordinates
				"mov t1.y, v0.y",
				// -------------
				"tex t0.xy, t1.xy, s0 <2d, clamp, nearest, mipnone>",	// get depth value
				"dp3 t2.z, t0.xyz, c0.xyz",								// decode value
				// -------------
				"sub t3.x, t2.z, t2.y",									// calculate Δz
				"div t3.y, t3.x, c2.x",
				"sat t3.z, t3.y",

				"add t3.w, t3.w, t3.z",									// calculate sum of Δz

				// 2 segment
				"add t1.x, v0.x, t4.z",
				"mov t1.y, v0.y",
				// -------------
				"tex t0.xy, t1.xy, s0 <2d, clamp, nearest, mipnone>",
				"dp3 t2.z, t0.xyz, c0.xyz",								// decode value
				// -------------
				"sub t3.x, t2.z, t2.y",									// calculate Δz
				"div t3.y, t3.x, c2.x",
				"sat t3.z, t3.y",

				"add t3.w, t3.w, t3.z",									// calculate sum of Δz

				// 3 segment
				"mov t1.x, v0.x",
				"add t1.y, v0.y, t4.y",
				// -------------
				"tex t0.xy, t1.xy, s0 <2d, clamp, nearest, mipnone>",
				"dp3 t2.z, t0.xyz, c0.xyz",								// decode value
				// -------------
				"sub t3.x, t2.z, t2.y",									// calculate Δz
				"div t3.y, t3.x, c2.x",
				"sat t3.z, t3.y",

				"add t3.w, t3.w, t3.z",									// calculate sum of Δz

				// 4 segment
				"mov t1.x, v0.x",
				"add t1.y, v0.y, t4.w",
				// -------------
				"tex t0.xy, t1.xy, s0 <2d, clamp, nearest, mipnone>",
				"dp3 t2.z, t0.xyz, c0.xyz",								// decode value
				// -------------
				"sub t3.x, t2.z, t2.y",									// calculate Δz
				"div t3.y, t3.x, c2.x",
				"sat t3.z, t3.y",

				"add t3.w, t3.w, t3.z",									// calculate sum of Δz

				// 5 segment
				"add t1.x, v0.x, t4.z",
				"add t1.y, v0.y, t4.y",
				// -------------
				"tex t0.xy, t1.xy, s0 <2d, clamp, nearest, mipnone>",
				"dp3 t2.z, t0.xyz, c0.xyz",								// decode value
				// -------------
				"sub t3.x, t2.z, t2.y",									// calculate Δz
				"div t3.y, t3.x, c2.x",
				"sat t3.z, t3.y",

				"add t3.w, t3.w, t3.z",									// calculate sum of Δz

				// 6 segment
				"add t1.x, v0.x, t4.x",
				"add t1.y, v0.y, t4.y",
				// -------------
				"tex t0.xy, t1.xy, s0 <2d, clamp, nearest, mipnone>",
				"dp3 t2.z, t0.xyz, c0.xyz",								// decode value
				// -------------
				"sub t3.x, t2.z, t2.y",									// calculate Δz
				"div t3.y, t3.x, c2.x",
				"sat t3.z, t3.y",

				"add t3.w, t3.w, t3.z",									// calculate sum of Δz

				// 7 segment
				"add t1.x, v0.x, t4.z",
				"add t1.y, v0.y, t4.w",
				// -------------
				"tex t0.xy, t1.xy, s0 <2d, clamp, nearest, mipnone>",
				"dp3 t2.z, t0.xyz, c0.xyz",								// decode value
				// -------------
				"sub t3.x, t2.z, t2.y",									// calculate Δz
				"div t3.y, t3.x, c2.x",
				"sat t3.z, t3.y",

				"add t3.w, t3.w, t3.z",									// calculate sum of Δz

				// 8 segment
				"add t1.x, v0.x, t4.x",
				"add t1.y, v0.y, t4.w",
				// -------------
				"tex t0.xy, t1.xy, s0 <2d, clamp, nearest, mipnone>",
				"dp3 t2.z, t0.xyz, c0.xyz",								// decode value
				// -------------
				"sub t3.x, t2.z, t2.y",									// calculate Δz
				"div t3.y, t3.x, c2.x",
				"sat t3.z, t3.y",

				"add t3.w, t3.w, t3.z",									// calculate sum of Δz

				// ------------
//				"mov t0.w, c0",
//				"mov t0.w, c1",
//				"mov t0.w, c2",

				"mul t3.w, t3.w, c2.z",		//  * 1/9

				"sub t3.w, c2.w, t3.w",		// 1 - sum of Δz
				"mul t3.w, t3.w, c2.y",		// multiplie sum of Δz
				"sub t3.w, c2.w, t3.w",		// 1 - sum of Δz

				"mov o0, t3.w"
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
			var camLength:Number = camera.farClipping - camera.nearClipping;
			drawUnit.setVertexConstantsFromNumbers(program.cScale, scaleX, scaleY, 0);
			drawUnit.setFragmentConstantsFromNumbers(program.cConstants, camLength, camLength/255, 0, 0);
			drawUnit.setFragmentConstantsFromNumbers(program.cOffset, offset/width, offset/height, -offset/width, -offset/height);

			drawUnit.setFragmentConstantsFromNumbers(program.cCoeff,   maxR, multiplier, 1/9, 1);
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
