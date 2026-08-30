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
