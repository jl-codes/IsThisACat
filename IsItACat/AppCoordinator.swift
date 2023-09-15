//
//  AppCoordinator.swift
//  IsItACat
//
//  Created by Tony Loehr on 9/15/23.
//

import Foundation
import UIKit

protocol Coordinator: AnyObject {
    var childCoordinators: [Coordinator] { get set }
    var navigationController: UINavigationController { get set }

    func start()
}

class AppCoordinator: Coordinator {
    var childCoordinators: [Coordinator] = []
    var navigationController: UINavigationController

    init(navigationController: UINavigationController = UINavigationController()) {
        self.navigationController = navigationController
    }

    func start() {
        let viewController = ViewController()
        navigationController.pushViewController(viewController, animated: false)
    }
}


