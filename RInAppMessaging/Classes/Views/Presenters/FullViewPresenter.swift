internal protocol FullViewPresenterType: BaseViewPresenterType {
    var view: FullViewType? { get set }

    func loadButtons()
    func didClickAction(sender: ActionButton)
    func didClickExitButton()
}

internal class FullViewPresenter: BaseViewPresenter, FullViewPresenterType {
    weak var view: FullViewType?

    override func viewDidInitialize() {
        let messagePayload = campaign.data.messagePayload
        let viewModel = FullViewModel(image: associatedImage,
                                      backgroundColor: UIColor(fromHexString: messagePayload.backgroundColor) ?? .white,
                                      title: messagePayload.title,
                                      messageBody: messagePayload.messageBody,
                                      messageLowerBody: messagePayload.messageLowerBody,
                                      header: messagePayload.header,
                                      titleColor: UIColor(fromHexString: messagePayload.titleColor) ?? .black,
                                      headerColor: UIColor(fromHexString: messagePayload.headerColor) ?? .black,
                                      messageBodyColor: UIColor(fromHexString: messagePayload.messageBodyColor) ?? .black,
                                      isHTML: messagePayload.messageSettings.displaySettings.html == true,
                                      showOptOut: messagePayload.messageSettings.displaySettings.optOut,
                                      showButtons: messagePayload.messageSettings.controlSettings?.buttons?.isEmpty == false)

        view?.setup(viewModel: viewModel)
    }

    func loadButtons() {
        guard let buttonList = campaign.data.messagePayload.messageSettings.controlSettings?.buttons else {
            return
        }

        let supportedButtons = buttonList.prefix(2).filter {
            [.redirect, .deeplink, .close].contains($0.buttonBehavior.action)
        }

        var buttonsToAdd = [(ActionButton, ActionButtonViewModel)]()
        for (index, button) in supportedButtons.enumerated() {
            buttonsToAdd.append((
                ActionButton(impression: index == 0 ? ImpressionType.actionOne : ImpressionType.actionTwo,
                             uri: button.buttonBehavior.uri,
                             trigger: button.campaignTrigger),
                ActionButtonViewModel(text: button.buttonText,
                                      textColor: UIColor(fromHexString: button.buttonTextColor) ?? .black,
                                      backgroundColor: UIColor(fromHexString: button.buttonBackgroundColor) ?? .white)))

        }

        view?.addButtons(buttonsToAdd)
    }

    func didClickAction(sender: ActionButton) {
        logImpression(type: sender.impression)
        checkOptOutStatus()
        sendImpressions()

        if let unwrappedUri = sender.uri {

            guard let uriToOpen = URL(string: unwrappedUri) else {
                if let view = view {
                    showURLError(view: view)
                }
                return
            }

            UIApplication.shared.open(uriToOpen, options: [:], completionHandler: { success in
                if !success, let view = self.view {
                    self.showURLError(view: view)
                }
            })
        }

        // If the button came with a campaign trigger, log it.
        handleButtonTrigger(sender.trigger)

        view?.dismiss()
    }

    func didClickExitButton() {
        logImpression(type: .exit)
        checkOptOutStatus()
        sendImpressions()

        view?.dismiss()
    }

    private func checkOptOutStatus() {
        guard view?.isOptOutChecked == true else {
            return
        }

        logImpression(type: .optOut)
        optOutCampaign()
    }
}
