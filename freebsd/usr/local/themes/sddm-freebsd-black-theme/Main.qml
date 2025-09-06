/***************************************************************************
*
* Permission is hereby granted, free of charge, to any person
* obtaining a copy of this software and associated documentation
* files (the "Software"), to deal in the Software without restriction,
* including without limitation the rights to use, copy, modify, merge,
* publish, distribute, sublicense, and/or sell copies of the Software,
* and to permit persons to whom the Software is furnished to do so,
* subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included
* in all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
* OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
* OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
* ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
* OR OTHER DEALINGS IN THE SOFTWARE.
*
***************************************************************************/

import QtQuick 2.0
import SddmComponents 2.0

Rectangle {

	width: 640
	height: 480

	TextConstants { id: textConstants }

		Connections {
			target: sddm

			onLoginSucceeded: {
				errorMessage.color = "#FFC627"
				errorMessage.text = textConstants.loginSucceeded
			}

			onLoginFailed: {
				errorMessage.color = "#EB0028"
				errorMessage.text = textConstants.loginFailed
			}
		}

		FontLoader {
			id: textFont; name: config.displayFont
		}

		Repeater {
			model: screenModel

			Background {
				x: geometry.x; y: geometry.y; width: geometry.width; height:geometry.height
				source: config.background
				fillMode: Image.Tile

				onStatusChanged: {
                        if (status == Image.Error && source !== config.defaultBackground) {
							source = config.defaultBackground
						}
				}
			}
		}

		Rectangle {
			property variant geometry: screenModel.geometry(screenModel.primary)
			x: geometry.x; y: geometry.y; width: geometry.width; height: geometry.height
			color: "transparent"
			transformOrigin: Item.Top

			Image {
				id: fbsdlogo
				anchors.centerIn: parent
				anchors.verticalCenterOffset: -1 * height / 2
				anchors.horizontalCenterOffset: 0
				width: height * 3
				height: parent.height / 6
				fillMode: Image.PreserveAspectFit
				transformOrigin: Item.Center

				source: "freebsd.png"
			}

			Rectangle {
				id: freebsd
				anchors.centerIn: parent
				anchors.verticalCenterOffset: height * 2 / 3
				width: height * 1.8
				height: parent.height / 10 * 3
				color: "#000000"

				Column {
					id: mainColumn
					anchors.centerIn: parent
					width: parent.width * 0.9
					spacing: freebsd.height / 22.5

					Text {
						anchors.horizontalCenter: parent.horizontalCenter
						verticalAlignment: Text.AlignVCenter
						width: parent.width
						height: text.implicitHeight
						color: "#FFFFFF"
						text: textConstants.welcomeText.arg(sddm.hostName)
						wrapMode: Text.WordWrap
						font.family: textFont.name
						font.pixelSize: freebsd.height / 11.75
						elide: Text.ElideRight
						horizontalAlignment: Text.AlignHCenter
					}

					Row {
						width: parent.width
						spacing: Math.round(freebsd.height / 70)

						Text {
							id: lblName
							width: parent.width * 0.20; height: freebsd.height / 9
							text: textConstants.userName
							verticalAlignment: Text.AlignVCenter
							font.family: textFont.name
							font.pixelSize: freebsd.height / 22.5
							font.bold: true
							color: "#FFFFFF"

						}

						TextBox {
							id: name
							width: parent.width * 0.8; height: freebsd.height / 9
							text: userModel.lastUser
							font.family: textFont.name
							font.pixelSize: freebsd.height / 20
							borderColor: "#8C8C8C"
							focusColor: "#EB0028"
							hoverColor: "#AB2B28"

							KeyNavigation.backtab: rebootButton; KeyNavigation.tab: password

								Keys.onPressed: {
									if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
										sddm.login(name.text, password.text, session.index)
										event.accepted = true
									}
								}
						}
				}

				Row {
					width: parent.width
					spacing : Math.round(freebsd.height / 70)

						Text {
							id: lblPassword
							width: parent.width * 0.2; height: freebsd.height / 9
							text: textConstants.password
							verticalAlignment: Text.AlignVCenter
							font.family: textFont.name
							font.pixelSize: freebsd.height / 22.5
							font.bold: true
							color: "#FFFFFF"
						}

						PasswordBox {
							id: password
							width: parent.width * 0.8; height: freebsd.height / 9
							font.family: textFont.name
							font.pixelSize: freebsd.height / 20
							borderColor: "#8C8C8C"
							focusColor: "#EB0028"
							hoverColor: "#AB2B28"

							image: "warning.png"

							KeyNavigation.backtab: name; KeyNavigation.tab: session

								Keys.onPressed: {
									if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
										sddm.login(name.text, password.text, session.index)
										event.accepted = true
									}
								}
						}
				}

				Row {
					spacing: Math.round(freebsd.height / 70)
					width: parent.width / 2
					z: 100

					Row {
						z: 100
						width: parent.width * 1.2
						spacing : Math.round(freebsd.height / 70)
						anchors.bottom: parent.bottom

						Text {
							id: lblSession
							width: parent.width / 3; height: freebsd.height / 9
							text: textConstants.session
							verticalAlignment: Text.AlignVCenter
							wrapMode: TextEdit.WordWrap
							font.family: textFont.name
							font.pixelSize: freebsd.height / 22.5
							font.bold: true
							color: "#FFFFFF"
						}

						ComboBox {
							id: session
							width: parent.width * 2 / 3; height: freebsd.height / 9
							font.family: textFont.name
							font.pixelSize: freebsd.height / 20
							borderColor: "#8C8C8C"
							focusColor: "#AB2B28"
							hoverColor: "#EB0028"

							arrowIcon: "angle-down.png"

							model: sessionModel
							index: sessionModel.lastIndex

							KeyNavigation.backtab: password; KeyNavigation.tab: layoutBox
						}
					}

					Row {
						z: 101
						width: parent.width * 0.8
						spacing : freebsd.height / 27
						anchors.bottom: parent.bottom

						Text {
							id: lblLayout
							width: parent.width / 3; height: freebsd.height / 9
							text: textConstants.layout
							verticalAlignment: Text.AlignVCenter
							horizontalAlignment: Text.AlignHCenter
							wrapMode: TextEdit.WordWrap
							font.family: textFont.name
							font.pixelSize: freebsd.height / 22.5
							font.bold: true
							color: "#FFFFFF"
						}

						LayoutBox {
							id: layoutBox
							width: (parent.width * 2 / 3) -10; height: freebsd.height / 9
							font.family: textFont.name
							font.pixelSize: freebsd.height / 20
							borderColor: "#8C8C8C"
							focusColor: "#AB2B28"
							hoverColor: "#EB0028"

							arrowIcon: "angle-down.png"

							KeyNavigation.backtab: session; KeyNavigation.tab: loginButton
						}
					}
				}

				Column {
					width: parent.width

					Text {
						id: errorMessage
						anchors.horizontalCenter: parent.horizontalCenter
						text: textConstants.prompt
						font.pixelSize: freebsd.height / 22.5
						color: "#FFFFFF"

					}
				}

				Row {
					spacing: Math.round(freebsd.height / 70)
					anchors.horizontalCenter: parent.horizontalCenter
					property int btnWidth: Math.max(loginButton.implicitWidth,
					shutdownButton.implicitWidth,
					rebootButton.implicitWidth, freebsd.height / 3) + 8

					Button {
						id: loginButton
						text: textConstants.login
						width: parent.btnWidth
						height: freebsd.height / 9
						font.pixelSize: freebsd.height / 20
						font.family: textFont.name
						color: "#AB2B28"
						activeColor: "#002E6D"
						pressedColor: "#EB0028"

						onClicked: sddm.login(name.text, password.text, session.index)

						KeyNavigation.backtab: layoutBox; KeyNavigation.tab: shutdownButton
					}

					Button {
						id: shutdownButton
							text: textConstants.shutdown
						width: parent.btnWidth
						height: freebsd.height / 9
						font.family: textFont.name
						font.pixelSize: freebsd.height / 20
						color: "#AB2B28"
						activeColor: "#002E6D"
						pressedColor: "#EB0028"

						onClicked: sddm.powerOff()

						KeyNavigation.backtab: loginButton; KeyNavigation.tab: rebootButton
					}

					Button {
						id: rebootButton
						text: textConstants.reboot
						width: parent.btnWidth
						height: freebsd.height / 9
						font.family: textFont.name
						font.pixelSize: freebsd.height / 20
						color: "#AB2B28"
						activeColor: "#002E6D"
						pressedColor: "#EB0028"

						onClicked: sddm.reboot()

						KeyNavigation.backtab: shutdownButton; KeyNavigation.tab: name
					}
				}
			}
		}
	}


	Component.onCompleted: {
        if (name.text === "")
			name.focus = true
		else
			password.focus = true
	}
}


