/*****************************************************************************************
 * GameViewController.swift
 *
 *
 *
 * Author   :  CompanyName <gary.ash@icloud.com>
 * Created  :   1-Sep-2026  4:42pm
 * Modified :
 *
 * Copyright © 2026 By Gary Ash All rights reserved.
 ****************************************************************************************/

import Cocoa
import GameplayKit
import SpriteKit

class GameViewController: NSViewController {
	override func viewDidLoad() {
		super.viewDidLoad()

		let scene = GameScene.newGameScene()

		// Present the scene
		let skView = view as! SKView
		skView.presentScene(scene)

		skView.ignoresSiblingOrder = true

		skView.showsFPS = true
		skView.showsNodeCount = true
	}
}
