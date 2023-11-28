import Foundation
import UIKit

#if SWIFT_PACKAGE
import RSDKUtilsMain
#else
import RSDKUtils
#endif

internal protocol TooltipTargetViewListenerType: AnyObject {
    func startListening()
    func stopListening()
    func addObserver(_ observer: TooltipTargetViewListenerObserver)
    func iterateOverDisplayedViews(_ handler: @escaping (_ view: UIView, _ identifier: String, _ stop: inout Bool) -> Void)
}

internal protocol TooltipTargetViewListenerObserver: AnyObject {
    func targetViewDidChangeSuperview(_ view: UIView, identifier: String)
    func targetViewDidMoveToWindow(_ view: UIView, identifier: String)
    func targetViewDidGetRemovedFromSuperview(_ view: UIView, identifier: String)
}

/// A class responsible for tracking UIView changes in the hierarchy.
/// All changes are reported to registered ViewListenerObserver objects.
/// This class is based on swizzling and MUST be used as a singleton to aviod unexpected behaviour.
/// - Note: SwiftUI owned windows are not supported.
internal final class TooltipTargetViewListener: TooltipTargetViewListenerType {

    // A static singleton-like value is necessary for UIView methods to access this class
    static private(set) var currentInstance = TooltipTargetViewListener()

    @AtomicGetSet private(set) var isListening = false
    fileprivate var observers = [WeakWrapper<TooltipTargetViewListenerObserver>]()
    private let windowGetter: () -> UIWindow?
    fileprivate var registeredViews = [String: WeakWrapper<UIView>]()
    fileprivate var registeredTabBarButtons = [String: WeakWrapper<UITabBarItem>]()

    private init(windowGetter: @escaping () -> UIWindow? = UIApplication.shared.getKeyWindow) {
        self.windowGetter = windowGetter
    }

    static func reinitialize(windowGetter: @escaping () -> UIWindow?) {
        currentInstance.stopListening()
        currentInstance = TooltipTargetViewListener(windowGetter: windowGetter)
    }

    func startListening() {
        guard !isListening else {
            return
        }

        isListening = true
        guard performSwizzling() else {
            isListening = false
            assertionFailure()
            _ = performSwizzling() // try to restore original implementations
            return
        }

//        iterateOverDisplayedViews { existingView, identifier, _ in
//            guard !identifier.isEmpty else {
//                return
//            }
//
//            existingView.didMoveToWindowNotifyObservers()
//        }
        registeredViews.forEach { identifier, viewContrainer in
            guard !identifier.isEmpty else {
                return
            }

            viewContrainer.value?.didMoveToWindowNotifyObservers()
        }
        // looking only for UITabBarButtons
        iterateOverDisplayedViews { displayedView, identifier, _ in
            guard !identifier.isEmpty else {
                return
            }

            displayedView.didMoveToWindowNotifyObservers()
        }
    }

    func stopListening() {
        guard isListening else {
            return
        }

        isListening = false
        guard performSwizzling() else {
            isListening = true
            assertionFailure()
            return
        }
    }

    func addObserver(_ observer: TooltipTargetViewListenerObserver) {
        observers.append(WeakWrapper(value: observer))
    }

    func iterateOverDisplayedViews(_ handler: @escaping (UIView, String, inout Bool) -> Void) {
        guard isListening else {
            return
        }
        DispatchQueue.main.async {
            guard let allWindowSubviews = self.windowGetter()?.getAllSubviewsExceptTooltipView()
                .filter({ !$0.tooltipIdentifier.isEmpty }) else {
                return
            }
            var stop = false
            for existingView in allWindowSubviews {
                guard !stop else {
                    return
                }
                let identifier = existingView.tooltipIdentifier
                guard !identifier.isEmpty else {
                    continue
                }
                handler(existingView, identifier, &stop)
            }
        }
    }

    func register(_ view: UIView, identifier: String) {
        registeredViews[identifier] = WeakWrapper(value: view)
    }

    func register(_ tabBarItem: UITabBarItem, identifier: String) {
        registeredTabBarButtons[identifier] = WeakWrapper(value: tabBarItem)
    }

    private func performSwizzling() -> Bool {
        [swizzle(#selector(UIView.didMoveToSuperview), with: #selector(UIView.swizzledDidMoveToSuperview)),
         swizzle(#selector(UIView.removeFromSuperview), with: #selector(UIView.swizzledRemoveFromSuperview)),
         swizzle(#selector(UIView.didMoveToWindow), with: #selector(UIView.swizzledDidMoveToWindow))].allSatisfy { $0 == true }
    }

    private func swizzle(_ sel1: Selector, with sel2: Selector, of classRef: AnyClass = UIView.self) -> Bool {
        guard let originalMethod = class_getInstanceMethod(classRef, sel1),
              let swizzledMethod = class_getInstanceMethod(classRef, sel2) else {
                  assertionFailure()
                  return false
              }

        method_exchangeImplementations(originalMethod, swizzledMethod)

        return true
    }
}

private extension UIView {

    var tooltipIdentifier: String {
        guard let tabBarParent = superview as? UITabBar else {
            // normal UIView
            return TooltipTargetViewListener.currentInstance.registeredViews.first(where: {
                $1.value === self
            })?.key ?? ""
        }

        guard let tabBarButton = self as? UIControl,
              let tabBarItem = tabBarParent.item(of: tabBarButton) else {
            return ""
        }

        return TooltipTargetViewListener.currentInstance.registeredTabBarButtons.first(where: {
            $1.value === tabBarItem
        })?.key ?? ""
    }

    // TOOLTIP: support isHidden

    @objc func swizzledDidMoveToSuperview() {
        self.swizzledDidMoveToSuperview()

        guard !tooltipIdentifier.isEmpty else {
            return
        }
        TooltipTargetViewListener.currentInstance.observers.forEach {
            $0.value?.targetViewDidChangeSuperview(self, identifier: tooltipIdentifier)
        }
    }

    @objc func swizzledRemoveFromSuperview() {
        self.swizzledRemoveFromSuperview()

        guard !tooltipIdentifier.isEmpty else {
            return
        }
        TooltipTargetViewListener.currentInstance.observers.forEach {
            $0.value?.targetViewDidGetRemovedFromSuperview(self, identifier: tooltipIdentifier)
        }
    }

    @objc func swizzledDidMoveToWindow() {
        self.swizzledDidMoveToWindow()

        guard !tooltipIdentifier.isEmpty else {
            return
        }
        didMoveToWindowNotifyObservers()
    }

    func didMoveToWindowNotifyObservers() {
        if window == nil {
            TooltipTargetViewListener.currentInstance.observers.forEach {
                $0.value?.targetViewDidGetRemovedFromSuperview(self, identifier: tooltipIdentifier)
            }
        } else {
            TooltipTargetViewListener.currentInstance.observers.forEach {
                $0.value?.targetViewDidMoveToWindow(self, identifier: tooltipIdentifier)
            }
        }
    }

    class func getAllSubviewsExceptTooltipView(from parentView: UIView) -> [UIView] {
        parentView.subviews.flatMap { subView -> [UIView] in
            guard !(subView is TooltipView) else {
                return []
            }
            var result = getAllSubviewsExceptTooltipView(from: subView)
            result.append(subView)
            return result
        }
    }

    func getAllSubviewsExceptTooltipView() -> [UIView] {
        UIView.getAllSubviewsExceptTooltipView(from: self)
    }
}
