/*
 * Copyright 2012, 2013, 2014 Canonical Ltd.
 *
 * This file is part of messaging-app.
 *
 * messaging-app is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * messaging-app is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.2
import QtQuick.Window 2.0
import Ubuntu.Components 1.1
import Ubuntu.Components.ListItems 0.1 as ListItem
import Ubuntu.Components.Popups 0.1
import Ubuntu.Content 0.1
import Ubuntu.History 0.1
import Ubuntu.Telephony 0.1
import Ubuntu.Contacts 0.1

import "dateUtils.js" as DateUtils

Page {
    id: messages
    objectName: "messagesPage"

    // this property can be overriden by the user using the account switcher,
    // in the suru divider
    property QtObject account: mainView.account

    property variant participants: []
    property variant previousParticipants: []
    property bool groupChat: participants.length > 1
    property bool keyboardFocus: true
    property alias selectionMode: messageList.isInSelectionMode
    // FIXME: MainView should provide if the view is in portait or landscape
    property int orientationAngle: Screen.angleBetween(Screen.primaryOrientation, Screen.orientation)
    property bool landscape: orientationAngle == 90 || orientationAngle == 270
    property var activeTransfer: null
    property int activeAttachmentIndex: -1
    property var sharedAttachmentsTransfer: []
    property alias contactWatcher: contactWatcherInternal
    property string lastFilter: ""
    property string text: ""
    property bool pendingMessage: false

    function addAttachmentsToModel(transfer) {
        for (var i = 0; i < transfer.items.length; i++) {
            var attachment = {}
            if (!startsWith(String(transfer.items[i].url),"file://")) {
                messages.text = String(transfer.items[i].url)
                continue
            }
            var filePath = String(transfer.items[i].url).replace('file://', '')
            // get only the basename
            attachment["contentType"] = application.fileMimeType(filePath)
            if (startsWith(attachment["contentType"], "text/vcard") ||
                startsWith(attachment["contentType"], "text/x-vcard")) {
                attachment["name"] = "contact.vcf"
            } else {
                attachment["name"] = filePath.split('/').reverse()[0]
            }
            attachment["filePath"] = filePath
            attachments.append(attachment)
        }
    }

    function checkNetwork() {
        return messages.account.connected;
    }

    function onPhonePickedDuringSearch(phoneNumber) {
        multiRecipient.addRecipient(phoneNumber)
        multiRecipient.clearSearch()
        multiRecipient.forceActiveFocus()
    }

    // this is necessary to automatically update the view when the
    // default account changes in system settings
    Connections {
        target: mainView
        onAccountChanged: messages.account = mainView.account
    }

    ListModel {
        id: attachments
    }

    PictureImport {
        id: pictureImporter

        onPictureReceived: {
            var attachment = {}
            var filePath = String(pictureUrl).replace('file://', '')
            attachment["contentType"] = application.fileMimeType(filePath)
            attachment["name"] = filePath.split('/').reverse()[0]
            attachment["filePath"] = filePath
            attachments.append(attachment)
            textEntry.forceActiveFocus()
        }
    }

    flickable: null

    property bool isReady: false
    signal ready
    onReady: {
        isReady = true
        if (participants.length === 0 && keyboardFocus)
            multiRecipient.forceFocus()
    }

    property string firstRecipientAlias: ""
    title: {
        if (selectionMode) {
            return " "
        }

        if (landscape) {
            return ""
        }
        if (participants.length > 0) {
            if (participants.length == 1) {
                return (firstRecipientAlias !== "") ? firstRecipientAlias : contactWatcher.phoneNumber
            } else {
                // TRANSLATORS: %1 refers to the number of participants in a group chat
                return i18n.tr("Group (%1)").arg(participants.length)
            }
        }
        return i18n.tr("New Message")
    }

    Component.onCompleted: {
        updateFilters()
        addAttachmentsToModel(sharedAttachmentsTransfer)
    }

    function updateFilters() {
        if (participants.length == 0) {
            eventModel.filter = null
            return
        }
        if (previousParticipants.join('') === participants.join('')) {
            return
        }
        var componentUnion = "import Ubuntu.History 0.1; HistoryUnionFilter { %1 }"
        var componentFilters = ""
        for (var i in telepathyHelper.accountIds) {
            var filterValue = eventModel.threadIdForParticipants(telepathyHelper.accountIds[i],
                                                                 HistoryThreadModel.EventTypeText,
                                                                 participants,
                                                                 HistoryThreadModel.MatchPhoneNumber)
            if (filterValue === "") {
                continue
            }
            componentFilters += 'HistoryFilter { filterProperty: "threadId"; filterValue: "%1" } '.arg(filterValue)
        }
        if (componentFilters === "") {
            eventModel.filter = null
            lastFilter = ""
            return
        }
        if (componentFilters != lastFilter) {
            var finalString = componentUnion.arg(componentFilters)
            eventModel.filter = Qt.createQmlObject(finalString, eventModel)
            lastFilter = componentFilters
            previousParticipants = participants
        }
    }

    function markMessageAsRead(accountId, threadId, eventId, type) {
        chatManager.acknowledgeMessage(participants[0], eventId, accountId)
        return eventModel.markEventAsRead(accountId, threadId, eventId, type);
    }

    Component {
        id: attachmentPopover

        Popover {
            id: popover
            Column {
                id: containerLayout
                anchors {
                    left: parent.left
                    top: parent.top
                    right: parent.right
                }
                ListItem.Standard {
                    text: i18n.tr("Remove")
                    onClicked: {
                        attachments.remove(activeAttachmentIndex)
                        PopupUtils.close(popover)
                    }
                }
            }
            Component.onDestruction: activeAttachmentIndex = -1
        }
    }

    Component {
        id: participantsPopover

        Popover {
            id: popover
            Column {
                id: containerLayout
                anchors {
                    left: parent.left
                    top: parent.top
                    right: parent.right
                }
                Repeater {
                    model: participants
                    Item {
                        height: childrenRect.height
                        width: popover.width
                        ListItem.Standard {
                            id: listItem
                            text: contactWatcher.isUnknown ? contactWatcher.phoneNumber : contactWatcher.alias
                        }
                        ContactWatcher {
                            id: contactWatcher
                            phoneNumber: modelData
                        }
                    }
                }
            }
        }
    }

    Component {
        id: noNetworkDialog
        Dialog {
            id: dialogue
            title: i18n.tr("No network")
            text: multipleAccounts ? i18n.tr("There is currently no network on %1").arg(messages.account.displayName) : i18n.tr("There is currently no network.")
            Button {
                objectName: "closeNoNetworkDialog"
                text: i18n.tr("Close")
                color: UbuntuColors.orange
                onClicked: {
                    PopupUtils.close(dialogue)
                    Qt.inputMethod.hide()
                }
            }
        }
    }

    head.sections.model: {
        // does not show dual sim switch if there is only one sim
        if (!multipleAccounts) {
            return undefined
        }

        var accountNames = []
        for(var i=0; i < telepathyHelper.activeAccounts.length; i++) {
            accountNames.push(telepathyHelper.activeAccounts[i].displayName)
        }
        return accountNames
    }
    head.sections.selectedIndex: {
        if (!messages.account) {
            return -1
        }
        for (var i in telepathyHelper.activeAccounts) {
            if (telepathyHelper.activeAccounts[i].accountId === messages.account.accountId) {
                return i
            }
        }
        return -1
    }
    Connections {
        target: messages.head.sections
        onSelectedIndexChanged: messages.account = telepathyHelper.activeAccounts[head.sections.selectedIndex]
    }

    Loader {
        id: searchListLoader

        property int resultCount: (status === Loader.Ready) ? item.count : 0

        source: (multiRecipient.searchString !== "") && multiRecipient.focus ?
                Qt.resolvedUrl("ContactSearchList.qml") : ""
        clip: true
        anchors {
            top: parent.top
            topMargin: units.gu(2)
            left: parent.left
            right: parent.right
        }
        z: 1
        Behavior on height {
            UbuntuNumberAnimation { }
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.palette.normal.background
        }

        Binding {
            target: searchListLoader.item
            property: "filterTerm"
            value: multiRecipient.searchString
            when: (searchListLoader.status === Loader.Ready)
        }

        Timer {
            id: checkHeight

            interval: 300
            repeat: false
            onTriggered: {
                searchListLoader.height = searchListLoader.resultCount > 0 ? searchListLoader.parent.height - keyboard.height : 0
            }
        }

        onStatusChanged: {
            if (status === Loader.Ready) {
                item.phonePicked.connect(messages.onPhonePickedDuringSearch)
            }
        }

        // WORKAROUND: Contact model get all contacts removed in every search, to avoid the view to blick
        // we will wait some msecs before reduce the size to 0 to confirm that there is no results on the view
        onResultCountChanged: {
            if (searchListLoader.resultCount > 0) {
                searchListLoader.height = searchListLoader.parent.height - keyboard.height
            } else {
                checkHeight.restart()
            }
        }

    }

    ContactWatcher {
        id: contactWatcherInternal
        phoneNumber: participants.length === 0 ? "" : participants[0]
        onIsUnknownChanged: firstRecipientAlias = contactWatcherInternal.alias
        onAliasChanged: firstRecipientAlias = contactWatcherInternal.alias
    }

    onParticipantsChanged: {
        updateFilters()
    }

    state: {
        if (participants.length === 0 && isReady) {
            return "newMessage"
        } else if (selectionMode) {
           return "selection"
        } else if (participants.length == 1) {
           if (contactWatcher.isUnknown) {
               return "unknownContact"
           } else {
               return "knownContact"
           }
        } else if (groupChat){
           return "groupChat"
        } else {
            return ""
        }
    }

    Action {
        id: backButton
        objectName: "backButton"
        iconName: "back"
        onTriggered: {
            if (typeof mainPage !== 'undefined') {
                mainPage.temporaryProperties = null
            }
            mainStack.pop()
        }
    }

    states: [
        PageHeadState {
            name: "selection"
            head: messages.head

            backAction: Action {
                objectName: "selectionModeCancelAction"
                iconName: "close"
                onTriggered: messageList.cancelSelection()
            }

            actions: [
                Action {
                    objectName: "selectionModeSelectAllAction"
                    iconName: "select"
                    onTriggered: {
                        if (messageList.selectedItems.count === messageList.count) {
                            messageList.clearSelection()
                        } else {
                            messageList.selectAll()
                        }
                    }
                },
                Action {
                    objectName: "selectionModeDeleteAction"
                    enabled: messageList.selectedItems.count > 0
                    iconName: "delete"
                    onTriggered: messageList.endSelection()
                }
            ]
        },
        PageHeadState {
            name: "groupChat"
            head: messages.head
            backAction: backButton

            actions: [
                Action {
                    objectName: "groupChatAction"
                    iconName: "contact-group"
                    onTriggered: PopupUtils.open(participantsPopover, messages.header)
                }
            ]
        },
        PageHeadState {
            name: "unknownContact"
            head: messages.head
            backAction: backButton

            actions: [
                Action {
                    objectName: "contactCallAction"
                    visible: participants.length == 1
                    iconName: "call-start"
                    text: i18n.tr("Call")
                    onTriggered: {
                        Qt.inputMethod.hide()
                        Qt.openUrlExternally("tel:///" + encodeURIComponent(contactWatcher.phoneNumber))
                    }
                },
                Action {
                    objectName: "addContactAction"
                    visible: contactWatcher.isUnknown && participants.length == 1
                    iconName: "new-contact"
                    text: i18n.tr("Add")
                    onTriggered: {
                        Qt.inputMethod.hide()
                        Qt.openUrlExternally("addressbook:///addnewphone?callback=messaging-app.desktop&phone=" + encodeURIComponent(contactWatcher.phoneNumber));
                    }
                }
            ]
        },
        PageHeadState {
            name: "newMessage"
            head: messages.head
            backAction: backButton
            actions: [
                Action {
                    objectName: "contactList"
                    iconName: "contact"
                    onTriggered: {
                        Qt.inputMethod.hide()
                        mainStack.push(Qt.resolvedUrl("NewRecipientPage.qml"), {"multiRecipient": multiRecipient, "parentPage": messages})
                    }
                }

            ]

            contents: MultiRecipientInput {
                id: multiRecipient
                objectName: "multiRecipient"
                enabled: visible
                anchors {
                    left: parent ? parent.left : undefined
                    right: parent ? parent.right : undefined
                    rightMargin: units.gu(2)
                }
            }
        },
        PageHeadState {
            name: "knownContact"
            head: messages.head
            backAction: backButton
            actions: [
                Action {
                    objectName: "contactCallKnownAction"
                    visible: participants.length == 1
                    iconName: "call-start"
                    text: i18n.tr("Call")
                    onTriggered: {
                        Qt.inputMethod.hide()
                        Qt.openUrlExternally("tel:///" + encodeURIComponent(contactWatcher.phoneNumber))
                    }
                },
                Action {
                    objectName: "contactProfileAction"
                    visible: !contactWatcher.isUnknown && participants.length == 1
                    iconSource: "image://theme/contact"
                    text: i18n.tr("Contact")
                    onTriggered: {
                        Qt.openUrlExternally("addressbook:///contact?callback=messaging-app.desktop&id=" + encodeURIComponent(contactWatcher.contactId))
                    }
                }
            ]
        }
    ]

    HistoryEventModel {
        id: eventModel
        type: HistoryThreadModel.EventTypeText
        filter: null
        sort: HistorySort {
           sortField: "timestamp"
           sortOrder: HistorySort.DescendingOrder
        }
        onCountChanged: {
            if (pendingMessage) {
                pendingMessage = false
                messageList.positionViewAtBeginning()
            }
        }
    }

    MessagesListView {
        id: messageList
        objectName: "messageList"

        // because of the header
        clip: true
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: bottomPanel.top
        }
    }

    Item {
        id: bottomPanel
        anchors.bottom: keyboard.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: selectionMode ? 0 : textEntry.height + units.gu(2)
        visible: !selectionMode
        clip: true
        MouseArea {
            anchors.fill: parent
            onClicked: {
                messageTextArea.forceActiveFocus()
            }
        }

        Behavior on height {
            UbuntuNumberAnimation { }
        }

        ListItem.ThinDivider {
            anchors.top: parent.top
        }

        Icon {
            id: attachButton
            anchors.left: parent.left
            anchors.leftMargin: units.gu(2)
            anchors.verticalCenter: sendButton.verticalCenter
            height: units.gu(3)
            width: units.gu(3)
            color: "gray"
            name: "camera-app-symbolic"
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    Qt.inputMethod.hide()
                    pictureImporter.requestNewPicture()
                }
            }
        }

        StyledItem {
            id: textEntry
            property alias text: messageTextArea.text
            property alias inputMethodComposing: messageTextArea.inputMethodComposing
            property int fullSize: attachmentThumbnails.height + messageTextArea.height
            style: Theme.createStyleComponent("TextFieldStyle.qml", textEntry)
            anchors.bottomMargin: units.gu(1)
            anchors.bottom: parent.bottom
            anchors.left: attachButton.right
            anchors.leftMargin: units.gu(1)
            anchors.right: sendButton.left
            anchors.rightMargin: units.gu(1)
            height: attachments.count !== 0 ? fullSize + units.gu(1.5) : fullSize
            onActiveFocusChanged: {
                if(activeFocus) {
                    messageTextArea.forceActiveFocus()
                } else {
                    focus = false
                }
            }
            focus: false
            MouseArea {
                anchors.fill: parent
                onClicked: messageTextArea.forceActiveFocus()
            }
            Flow {
                id: attachmentThumbnails
                spacing: units.gu(1)
                anchors{
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    topMargin: units.gu(1)
                    leftMargin: units.gu(1)
                    rightMargin: units.gu(1)
                }
                height: childrenRect.height

                Component {
                    id: thumbnailImage
                    UbuntuShape {
                        property int index
                        property string filePath

                        width: childrenRect.width
                        height: childrenRect.height

                        image: Image {
                            id: avatarImage
                            width: units.gu(8)
                            height: units.gu(8)
                            fillMode: Image.PreserveAspectCrop
                            source: filePath
                            asynchronous: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                mouse.accept = true
                                Qt.inputMethod.hide()
                                activeAttachmentIndex = index
                                PopupUtils.open(attachmentPopover, parent)
                            }
                            onPressAndHold: clicked(mouse)
                        }
                    }
                }

                Component {
                    id: thumbnailContact
                    Item {
                        id: attachment

                        property int index
                        property string filePath

                        height: units.gu(6)
                        width: textEntry.width

                        ContactAvatar {
                            id: avatar

                            anchors {
                                top: parent.top
                                bottom: parent.bottom
                                left: parent.left
                            }
                            fallbackAvatarUrl: "image://theme/contact"
                            fallbackDisplayName: label.name
                            width: height
                        }
                        Label {
                            id: label

                            property string name: attachment.filePath != "" ? application.contactNameFromVCard(attachment.filePath) : ""

                            anchors {
                                left: avatar.right
                                leftMargin: units.gu(1)
                                top: avatar.top
                                bottom: avatar.bottom
                                right: parent.right
                            }

                            verticalAlignment: Text.AlignVCenter
                            text: name !== "" ? name : i18n.tr("Unknown contact")
                            elide: Text.ElideRight
                            color: UbuntuColors.lightAubergine
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                mouse.accept = true
                                Qt.inputMethod.hide()
                                activeAttachmentIndex = index
                                PopupUtils.open(attachmentPopover, parent)
                            }
                            onPressAndHold: clicked(mouse)
                        }
                    }
                }

                Component {
                    id: thumbnailUnknown

                    UbuntuShape {
                        property int index
                        property string filePath

                        width: units.gu(8)
                        height: units.gu(8)

                        Icon {
                            anchors.centerIn: parent
                            width: units.gu(6)
                            height: units.gu(6)
                            name: "attachment"
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                mouse.accept = true
                                Qt.inputMethod.hide()
                                activeAttachmentIndex = index
                                PopupUtils.open(attachmentPopover, parent)
                            }
                            onPressAndHold: clicked(mouse)
                        }
                    }
                }

                Repeater {
                    model: attachments
                    delegate: Loader {
                        height: units.gu(8)
                        sourceComponent: {
                            var contentType = getContentType(filePath)
                            console.log(contentType)
                            switch(contentType) {
                            case ContentType.Contacts:
                                return thumbnailContact
                            case ContentType.Pictures:
                                return thumbnailImage
                            case ContentType.Unknown:
                                return thumbnailUnknown
                            default:
                                console.log("unknown content Type")
                            }
                        }
                        onStatusChanged: {
                            if (status == Loader.Ready) {
                                item.index = index
                                item.filePath = filePath
                            }
                        }
                    }
                }
            }

            ListItem.ThinDivider {
                id: divider

                anchors {
                    left: parent.left
                    right: parent.right
                    top: attachmentThumbnails.bottom
                    margins: units.gu(0.5)
                }
                visible: attachments.count > 0
            }

            TextArea {
                id: messageTextArea
                anchors {
                    top: attachments.count == 0 ? textEntry.top : attachmentThumbnails.bottom
                    left: parent.left
                    right: parent.right
                }
                // this value is to avoid letter being cut off
                height: units.gu(4.3)
                style: MultiRecipientFieldStyle {}
                autoSize: true
                maximumLineCount: attachments.count == 0 ? 8 : 4
                placeholderText: i18n.tr("Write a message...")
                focus: textEntry.focus
                font.family: "Ubuntu"
                font.pixelSize: FontUtils.sizeToPixels("medium")
                color: "#5d5d5d"
                text: messages.text
            }

            /*InverseMouseArea {
                anchors.fill: parent
                visible: textEntry.activeFocus
                onClicked: {
                    textEntry.focus = false;
                }
            }*/
            Component.onCompleted: {
                // if page is active, it means this is not a bottom edge page
                if (messages.active && messages.keyboardFocus && participants.length != 0) {
                    messageTextArea.forceActiveFocus()
                }
            }
        }

        Button {
            id: sendButton
            objectName: "sendButton"
            anchors.bottomMargin: units.gu(1)
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.rightMargin: units.gu(2)
            text: i18n.tr("Send")
            color: enabled ? "#38b44a" : "#b2b2b2"
            width: units.gu(7)
            height: units.gu(4)
            font.pixelSize: FontUtils.sizeToPixels("small")
            activeFocusOnPress: false
            enabled: {
               if (participants.length > 0 || multiRecipient.recipientCount > 0 || multiRecipient.searchString !== "") {
                    if (textEntry.text != "" || textEntry.inputMethodComposing || attachments.count > 0) {
                        return true
                    }
                }
                return false
            }
            onClicked: {
                // check if at least one account is selected
                if (!messages.account) {
                    Qt.inputMethod.hide()
                    PopupUtils.open(Qt.createComponent("Dialogs/NoSIMCardSelectedDialog.qml").createObject(messages))
                    return
                }
                if (!checkNetwork()) {
                    Qt.inputMethod.hide()
                    PopupUtils.open(noNetworkDialog)
                    return
                }
                if (multipleAccounts && !telepathyHelper.defaultMessagingAccount && !settings.messagesDontAsk) {
                    PopupUtils.open(Qt.createComponent("Dialogs/SetDefaultSIMCardDialog.qml").createObject(messages))
                }
                // make sure we flush everything we have prepared in the OSK preedit
                Qt.inputMethod.commit();
                if (textEntry.text == "" && attachments.count == 0) {
                    return
                }
                // refresh the recipient list
                multiRecipient.focus = false
                // dont change the participants list
                if (participants.length == 0) {
                    participants = multiRecipient.recipients
                }
                // create the new thread and update the threadId list
                eventModel.threadIdForParticipants(messages.account.accountId,
                                                   HistoryThreadModel.EventTypeText,
                                                   participants,
                                                   HistoryThreadModel.MatchPhoneNumber,
                                                   true)

                updateFilters()
                if (attachments.count > 0) {
                    var newAttachments = []
                    for (var i = 0; i < attachments.count; i++) {
                        var attachment = []
                        var item = attachments.get(i)
                        attachment.push(item.name)
                        attachment.push(item.contentType)
                        attachment.push(item.filePath)
                        newAttachments.push(attachment)
                    }
                    pendingMessage = true
                    chatManager.sendMMS(participants, textEntry.text, newAttachments, messages.account.accountId)
                    textEntry.text = ""
                    attachments.clear()
                    return
                }

                pendingMessage = true
                chatManager.sendMessage(participants, textEntry.text, messages.account.accountId)
                textEntry.text = ""
            }
        }
    }

    KeyboardRectangle {
        id: keyboard
    }

    MessageInfoDialog {
        id: messageInfoDialog
    }
}
