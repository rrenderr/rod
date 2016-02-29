import strutils, tables
import nimx.view
import nimx.text_field
import nimx.button
import nimx.matrixes
import nimx.menu
import variant

export view

import panel_view
import node
import component
import rod_types

import property_visitor
import property_editors.propedit_registry
import property_editors.standard_editors

type InspectorView* = ref object of PanelView
    nameTextField: TextField

method init*(i: InspectorView, r: Rect) =
    procCall i.PanelView.init(r)
    i.collapsible = true
    i.collapsed = true
    let title = newLabel(newRect(22, 6, 100, 15))
    title.textColor = whiteColor()
    title.text = "Properties"
    i.addSubview(title)
    i.autoresizingMask = { afFlexibleMaxX }

proc newSectionTitle(y: Coord, inspector: InspectorView, n: Node3D, name: string): View
proc createNewComponentButton(y: Coord, inspector: InspectorView, n: Node3D): View

proc `inspectedNode=`*(i: InspectorView, n: Node3D) =
    if i.subviews.len > 1:
        i.subviews[1].removeFromSuperview()
    if not n.isNil:
        let propView = View.new(newRect(1, 29, i.bounds.width - 3, i.bounds.height - 40))
        propView.autoresizingMask = {afFlexibleWidth, afFlexibleHeight}

        var y = Coord(0)
        var pv: View
        var visitor : PropertyVisitor
        visitor.requireName = true
        visitor.requireSetter = true
        visitor.requireGetter = true
        visitor.flags = { pfEditable }
        visitor.commit = proc() =
            pv = propertyEditorForProperty(n, visitor.name, visitor.setterAndGetter)
            pv.setFrameOrigin(newPoint(0, y))
            y += pv.frame.height
            propView.addSubview(pv)

        n.visitProperties(visitor)

        if not n.components.isNil:
            for k, v in n.components:
                pv = newSectionTitle(y, i, n, k)
                y += pv.frame.height
                propView.addSubview(pv)
                v.visitProperties(visitor)

        pv = createNewComponentButton(y, i, n)
        y += pv.frame.height
        propView.addSubview(pv)

        var fs = propView.frame.size
        fs.height = y
        propView.setFrameSize(fs)
        i.addSubview(propView)

        if i.collapsible:
            if i.collapsed:
                i.collapsed = false
                i.setFrameSize(newSize(i.frame.size.width, if i.collapsed: 27.Coord else: i.fullHeight))
                i.setNeedsDisplay()
    else:
        if i.collapsible:
            if not i.collapsed:
                i.collapsed = true
                i.setFrameSize(newSize(i.frame.size.width, if i.collapsed: 27.Coord else: i.fullHeight))
                i.setNeedsDisplay()

proc newSectionTitle(y: Coord, inspector: InspectorView, n: Node3D, name: string): View =
    result = View.new(newRect(0, y, 240, 17))
    let v = newLabel(newRect(5, 0, 100, 15))
    v.text = name
    v.textColor = newGrayColor(0.9)
    result.addSubview(v)

    let removeButton = newButton(newRect(result.bounds.width - 20, 0, 20, 17))
    removeButton.autoresizingMask = {afFlexibleMinX, afFlexibleMaxY}
    removeButton.title = "-"
    removeButton.onAction do():
        n.removeComponent(name)
        inspector.inspectedNode = n
    result.addSubview(removeButton)

proc createNewComponentButton(y: Coord, inspector: InspectorView, n: Node3D): View =
    let b = Button.new(newRect(0, y, 120, 20))
    b.title = "New component"
    b.onAction do():
        var menu : Menu
        menu.new()
        var items = newSeq[MenuItem]()
        for i, c in registeredComponents():
            let menuItem = newMenuItem(c)
            let pWorkaroundForJS = proc(mi: MenuItem): proc() =
                result = proc() =
                    discard n.component(mi.title)
                    inspector.inspectedNode = n

            menuItem.action = pWorkaroundForJS(menuItem)
            items.add(menuItem)

        menu.items = items
        menu.popupAtPoint(b, newPoint(0, b.bounds.height))
    result = b
