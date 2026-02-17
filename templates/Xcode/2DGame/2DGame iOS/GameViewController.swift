/*****************************************************************************************
 * GameViewController.swift
 *
 *
 *
 * Author   :  CompanyName <gary.ash@icloud.com>
 * Created  :  20-Feb-2026  5:21pm
 * Modified :
 *
 * Copyright © 2026 By CompanyName All rights reserved.
 ****************************************************************************************/

import GameplayKit
import SpriteKit
import UIKit

class GameViewController: UIViewController {
	override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
		if UIDevice.current.userInterfaceIdiom == .phone {
			return .allButUpsideDown
		} else {
			return .all
		}
	}

	override var prefersStatusBarHidden: Bool {
		return true
	}

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
