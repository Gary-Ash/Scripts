/*****************************************************************************************
 * GameScene.swift
 *
 *
 *
 * Author   :  CompanyName <gary.ash@icloud.com>
 * Created  :  20-Feb-2026  5:21pm
 * Modified :
 *
 * Copyright © 2026 By CompanyName All rights reserved.
 ****************************************************************************************/

import SpriteKit

class GameScene: SKScene {
	override func didMove(to _: SKView) {
		setUpScene()
	}

	override func update(_: TimeInterval) {
		// Called before each frame is rendered
	}

	class func newGameScene() -> GameScene {
		// Load 'GameScene.sks' as an SKScene.
		guard let scene = SKScene(fileNamed: "GameScene") as? GameScene else {
			print("Failed to load GameScene.sks")
			abort()
		}

		// Set the scale mode to scale to fit the window
		scene.scaleMode = .aspectFill

		return scene
	}

	func setUpScene() {
		// Get label node from scene and store it for use later
		label = childNode(withName: "//helloLabel") as? SKLabelNode
		if let label {
			label.alpha = 0.0
			label.run(SKAction.fadeIn(withDuration: 2.0))
		}

		// Create shape node to use during mouse interaction
		let w = (size.width + size.height) * 0.05
		spinnyNode = SKShapeNode(rectOf: CGSize(width: w, height: w), cornerRadius: w * 0.3)

		if let spinnyNode {
			spinnyNode.lineWidth = 4.0
			spinnyNode.run(SKAction.repeatForever(SKAction.rotate(byAngle: CGFloat(Double.pi), duration: 1)))
			spinnyNode.run(SKAction.sequence([SKAction.wait(forDuration: 0.5),
			                                  SKAction.fadeOut(withDuration: 0.5),
			                                  SKAction.removeFromParent()]))
		}
	}

	func makeSpinny(at pos: CGPoint, color: SKColor) {
		if let spinny = spinnyNode?.copy() as! SKShapeNode? {
			spinny.position = pos
			spinny.strokeColor = color
			addChild(spinny)
		}
	}

	fileprivate var label: SKLabelNode?
	fileprivate var spinnyNode: SKShapeNode?
}

#if os(iOS) || os(tvOS)
	/// Touch-based event handling
	extension GameScene {
		override func touchesBegan(_ touches: Set<UITouch>, with _: UIEvent?) {
			if let label {
				label.run(SKAction(named: "Pulse")!, withKey: "fadeInOut")
			}

			for t in touches {
				makeSpinny(at: t.location(in: self), color: SKColor.green)
			}
		}

		override func touchesMoved(_ touches: Set<UITouch>, with _: UIEvent?) {
			for t in touches {
				makeSpinny(at: t.location(in: self), color: SKColor.blue)
			}
		}

		override func touchesEnded(_ touches: Set<UITouch>, with _: UIEvent?) {
			for t in touches {
				makeSpinny(at: t.location(in: self), color: SKColor.red)
			}
		}

		override func touchesCancelled(_ touches: Set<UITouch>, with _: UIEvent?) {
			for t in touches {
				makeSpinny(at: t.location(in: self), color: SKColor.red)
			}
		}
	}
#endif

#if os(OSX)
	/// Mouse-based event handling
	extension GameScene {
		override func mouseDown(with event: NSEvent) {
			if let label {
				label.run(SKAction(named: "Pulse")!, withKey: "fadeInOut")
			}
			makeSpinny(at: event.location(in: self), color: SKColor.green)
		}

		override func mouseDragged(with event: NSEvent) {
			makeSpinny(at: event.location(in: self), color: SKColor.blue)
		}

		override func mouseUp(with event: NSEvent) {
			makeSpinny(at: event.location(in: self), color: SKColor.red)
		}
	}
#endif
