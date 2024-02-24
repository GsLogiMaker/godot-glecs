
use std::fmt::Debug;
use std::rc::Rc;
use std::mem::size_of;

use flecs::EntityId;
use godot::engine::notify::ObjectNotification;
use godot::prelude::*;

use crate::component_definitions::ComponetDefinition;
use crate::component_definitions::ComponetProperty;
use crate::entity::FREED_BY_ENTITY_TAG;
use crate::show_error;
use crate::world::_BaseGEWorld;

/// An ECS component.
#[derive(GodotClass)]
#[class(base=Object)]
pub struct _BaseGEComponent {
    #[base] pub(crate) base: Base<Object>,
    pub(crate) component_definition: Rc<ComponetDefinition>,
    pub(crate) world: Gd<_BaseGEWorld>,
    pub(crate) get_data_fn_ptr: Box<dyn Fn(&Self) -> *mut [u8]>,
}
#[godot_api]
impl _BaseGEComponent {
    #[func]
    fn _on_register(world:Gd<_BaseGEWorld>) {}

    /// Copies the data from the given component to this one.
    #[func]
    fn copy_from_component(&mut self, from_component:Gd<_BaseGEComponent>) {
        if self.get_flecs_id() != from_component.bind().get_flecs_id() {
            show_error!(
                "Failed to copy component",
                "Destination component is of type {}, but source component is of type {}",
                self.base().get_script(),
                from_component.bind().base().get_script(),
            )
        }
        unsafe {
            self.get_data().as_mut().unwrap().copy_from_slice(
                from_component.bind().get_data().as_ref().unwrap(),
            );
        }
    }

    /// Returns the name of the the type of this component.
    #[func]
    fn get_component_type_name(&self) -> StringName {
        self.component_definition.name.clone()
    }

    /// Returns a property from the component data.
    #[func]
    fn getc(&self, property: StringName) -> Variant {
        let v = self._get_property(property.clone());
        if v == Variant::nil() {
            show_error!(
                "Failed to get property",
                "No property named \"{}\" in component of type \"{}\"",
                property,
                self.get_component_type_name(),
            );
        }
        v
    }

    /// Sets a property in the component data.
    #[func]
    fn setc(&mut self, property: StringName, value:Variant) {
        if !self._set_property(property.clone(), value.clone()) {
            show_error!(
                "Failed to set property",
                "No property named \"{}\" in component of type \"{}\"",
                property,
                self.get_component_type_name(),
            );
        }
    }

    /// Prevent user from freeing a component.
    #[func]
    fn free(&self) {
        return;
    }

    pub(crate) fn new_default_data_getter(entity:EntityId) -> Box<dyn Fn(&Self) -> *mut [u8]> {
        Box::new(move |this| {
            let value = unsafe { flecs::ecs_get_mut_id(
                this.world.bind().world.raw(),
                entity,
                this.get_flecs_id(),
            ) };
            unsafe { std::slice::from_raw_parts_mut(
                value as *mut u8,
                this.component_definition.layout.size(),
            ) }
        })
    }

    pub(crate) fn new_empty_data_getter() -> Box<dyn Fn(&Self) -> *mut [u8]> {
        Box::new(|_this| { &mut [] })
    }

    fn get_data(&self) -> *mut [u8] {
        ( &(*self.get_data_fn_ptr) )(self)
    }

    /// Returns the Flecs ID of this component's type.
    pub(crate) fn get_flecs_id(&self) -> EntityId {
        self.component_definition.flecs_id
    }

    pub(crate) fn _get_property(
		&self,
		property:StringName,
	) -> Variant {
        let Some(property_data) = self
            .component_definition
            .get_property(&property)
            else {
                return Variant::nil();
            };
        
        fn get_param<T: ToGodot + Clone + Debug>(
            data:*mut [u8],
            property_data: &ComponetProperty
        ) -> Variant {
            unsafe {
                let param:*mut u8 = &mut (*data)[property_data.offset];
                let value = param as *mut T;
                let copied = (*value).clone();
                let variant = Variant::from(copied);
                return variant;
            }
        }

        fn get_param_variant(
            data:*mut [u8],
            property_data: &ComponetProperty
        ) -> Variant {
            unsafe {
                let param:*mut u8 = &mut (*data)[property_data.offset];
                let value = param as *mut Variant;
                let copied = (*value).clone();
                return copied;
            }
        }
        
        let data = self.get_data();
        let value =  match property_data.gd_type_id {
            VariantType::Nil => Variant::nil(),
            VariantType::Bool => get_param::<bool>(data, property_data),
            VariantType::Int => get_param::<i32>(data, property_data),
            VariantType::Float => get_param::<f32>(data, property_data),
            VariantType::String => get_param::<GString>(data, property_data),
            VariantType::Vector2 => get_param::<Vector2>(data, property_data),
            VariantType::Vector2i => get_param::<Vector2i>(data, property_data),
            VariantType::Rect2 => get_param::<Rect2>(data, property_data),
            VariantType::Rect2i => get_param::<Rect2i>(data, property_data),
            VariantType::Vector3 => get_param::<Vector3>(data, property_data),
            VariantType::Vector3i => get_param::<Vector3i>(data, property_data),
            VariantType::Transform2D => get_param::<Transform2D>(data, property_data),
            VariantType::Vector4 => get_param::<Vector4>(data, property_data),
            VariantType::Vector4i => get_param::<Vector4i>(data, property_data),
            VariantType::Plane => get_param::<Plane>(data, property_data),
            VariantType::Quaternion => get_param::<Quaternion>(data, property_data),
            VariantType::Aabb => get_param::<Aabb>(data, property_data),
            VariantType::Basis => get_param::<Basis>(data, property_data),
            VariantType::Transform3D => get_param::<Transform3D>(data, property_data),
            VariantType::Projection => get_param::<Projection>(data, property_data),
            VariantType::Color => get_param::<Color>(data, property_data),
            VariantType::StringName => get_param::<StringName>(data, property_data),
            VariantType::NodePath => get_param::<NodePath>(data, property_data),
            VariantType::Rid => get_param::<Rid>(data, property_data),
            VariantType::Object => get_param_variant(data, property_data),
            VariantType::Callable => get_param::<Callable>(data, property_data),
            VariantType::Signal => get_param::<Signal>(data, property_data),
            VariantType::Dictionary => get_param_variant(data, property_data),
            VariantType::Array => get_param_variant(data, property_data),
            VariantType::PackedByteArray => get_param::<PackedByteArray>(data, property_data),
            VariantType::PackedInt32Array => get_param::<PackedInt32Array>(data, property_data),
            VariantType::PackedInt64Array => get_param::<PackedInt64Array>(data, property_data),
            VariantType::PackedFloat32Array => get_param::<PackedFloat32Array>(data, property_data),
            VariantType::PackedFloat64Array => get_param::<PackedFloat64Array>(data, property_data),
            VariantType::PackedStringArray => get_param::<PackedStringArray>(data, property_data),
            VariantType::PackedVector2Array => get_param::<PackedVector2Array>(data, property_data),
            VariantType::PackedVector3Array => get_param::<PackedVector3Array>(data, property_data),
            VariantType::PackedColorArray => get_param::<PackedColorArray>(data, property_data),

            _ => todo!(),
        };
        value
    }

    pub(crate) fn _set_property(
		&mut self,
		property:StringName,
		value:Variant,
	) -> bool {
        let Some(property_data) = self
            .component_definition
            .get_property(&property) else {
                return false;
            };

        let value_type = value.get_type();
        let property_type = property_data.gd_type_id;
        'cancel_type_check: {
            if value_type != property_type {
                if
                property_type == VariantType::Object
                    && value_type == VariantType::Nil
                { break 'cancel_type_check }

                show_error!(
                    "Failed to set property",
                    "Expected type {:?}, but got type {:?}.",
                    property_type,
                    value_type,
                );
                return true;
            }
        }
        
        fn set_param<T: FromGodot + ToGodot + Debug + Clone>(
            data:*mut [u8],
            value: Variant,
            property_data: &ComponetProperty,
        ) {
            unsafe {
                let param_ptr:*mut u8 = &mut (*data)[property_data.offset];
                *(param_ptr as *mut T) = value.to::<T>();
            }
        }

        fn set_param_variant(
            data:*mut [u8],
            value: Variant,
            property_data: &ComponetProperty,
        ) {
            unsafe {
                let param_ptr = (
                    ( &mut (*data)[property_data.offset] ) as *mut u8
                ).cast::<Variant>();
                *param_ptr = value;
            }
        }
        
        let data = self.get_data();
        match property_type {
            VariantType::Nil => {},
            VariantType::Bool => set_param::<bool>(data, value, property_data),
            VariantType::Int => set_param::<i32>(data, value, property_data),
            VariantType::Float => set_param::<f32>(data, value, property_data),
            VariantType::String => set_param::<GString>(data, value, property_data),
            VariantType::Vector2 => set_param::<Vector2>(data, value, property_data),
            VariantType::Vector2i => set_param::<Vector2i>(data, value, property_data),
            VariantType::Rect2 => set_param::<Rect2>(data, value, property_data),
            VariantType::Rect2i => set_param::<Rect2i>(data, value, property_data),
            VariantType::Vector3 => set_param::<Vector3>(data, value, property_data),
            VariantType::Vector3i => set_param::<Vector3i>(data, value, property_data),
            VariantType::Transform2D => set_param::<Transform2D>(data, value, property_data),
            VariantType::Vector4 => set_param::<Vector4>(data, value, property_data),
            VariantType::Vector4i => set_param::<Vector4i>(data, value, property_data),
            VariantType::Plane => set_param::<Plane>(data, value, property_data),
            VariantType::Quaternion => set_param::<Quaternion>(data, value, property_data),
            VariantType::Aabb => set_param::<Aabb>(data, value, property_data),
            VariantType::Basis => set_param::<Basis>(data, value, property_data),
            VariantType::Transform3D => set_param::<Transform3D>(data, value, property_data),
            VariantType::Projection => set_param::<Projection>(data, value, property_data),
            VariantType::Color => set_param::<Color>(data, value, property_data),
            VariantType::StringName => set_param::<StringName>(data, value, property_data),
            VariantType::NodePath => set_param::<NodePath>(data, value, property_data),
            VariantType::Rid => set_param::<Rid>(data, value, property_data),
            VariantType::Object => set_param_variant(data, value, property_data),
            VariantType::Callable => set_param::<Callable>(data, value, property_data),
            VariantType::Signal => set_param::<Signal>(data, value, property_data),
            VariantType::Dictionary => set_param_variant(data, value, property_data),
            VariantType::Array => set_param_variant(data, value, property_data),
            VariantType::PackedByteArray => set_param::<PackedByteArray>(data, value, property_data),
            VariantType::PackedInt32Array => set_param::<PackedInt32Array>(data, value, property_data),
            VariantType::PackedInt64Array => set_param::<PackedInt64Array>(data, value, property_data),
            VariantType::PackedFloat32Array => set_param::<PackedFloat32Array>(data, value, property_data),
            VariantType::PackedFloat64Array => set_param::<PackedFloat64Array>(data, value, property_data),
            VariantType::PackedStringArray => set_param::<PackedStringArray>(data, value, property_data),
            VariantType::PackedVector2Array => set_param::<PackedVector2Array>(data, value, property_data),
            VariantType::PackedVector3Array => set_param::<PackedVector3Array>(data, value, property_data),
            VariantType::PackedColorArray => set_param::<PackedColorArray>(data, value, property_data),

            _ => todo!(),
        }

        return true;
    }

    // Similar to [_set_property], except it does not call the destructor.
    pub(crate) fn _initialize_property(
        data:&mut [u8],
        description:&ComponetDefinition,
        property:StringName,
        value:Variant, // TODO: Utilize the initialization value
    ) -> bool {
        let Some(property_data) = description
            .get_property(&property) else {
                show_error!(
                    "Property initialization failed",
                    "Can't write to {} in {{component}}. Component has no property with that name",
                    property,
                );
                return false;
            };

        let value_type = value.get_type();
        let property_type = property_data.gd_type_id;
        if value_type != property_type && value_type != VariantType::Nil{
            show_error!(
                "Failed to set property",
                "Expected type {:?}, but got type {:?}.",
                property_type,
                value_type,
            );
            return true;
        }
        
        fn init_param<T: FromGodot + ToGodot + Debug + Clone>(
            data:*mut [u8],
            value: Variant,
            property_data: &ComponetProperty,
            default: &dyn Fn() -> Variant,
        ) {
             let default_value = if value != Variant::nil() {
                value
            } else {
                (default)()
            };
            unsafe {
                let param_ptr:*mut u8 = &mut (*data)[property_data.offset];
                let param_slice = std::slice::from_raw_parts_mut(param_ptr, size_of::<T>());
                let value_ptr:*const T = &default_value.to::<T>();
                let value_slice = std::slice::from_raw_parts(value_ptr as *const u8, size_of::<T>());
                param_slice.copy_from_slice(value_slice);
            }
        }

        fn init_param_variant(
            data:*mut [u8],
            value: Variant,
            property_data: &ComponetProperty,
        ) {
            let default_value = if value != Variant::nil() {
                value
            } else {
                Variant::default()
            };
            unsafe {
                let param_ptr:*mut u8 = &mut (*data)[property_data.offset];
                let param_slice = std::slice::from_raw_parts_mut(param_ptr, size_of::<Variant>());
                let value_ptr:*const Variant = &default_value;
                let value_slice = std::slice::from_raw_parts(value_ptr as *const u8, size_of::<Variant>());
                param_slice.copy_from_slice(value_slice);
            }
        }

        match property_data.gd_type_id {
            VariantType::Nil => {},
            VariantType::Bool => init_param::<bool>(data, value, property_data, &|| bool::default().to_variant()),
            VariantType::Int => init_param::<i32>(data, value, property_data, &|| i32::default().to_variant()),
            VariantType::Float => init_param::<f32>(data, value, property_data, &|| f32::default().to_variant()),
            VariantType::String => init_param::<GString>(data, value, property_data, &|| GString::default().to_variant()),
            VariantType::Vector2 => init_param::<Vector2>(data, value, property_data, &|| Vector2::default().to_variant()),
            VariantType::Vector2i => init_param::<Vector2i>(data, value, property_data, &|| Vector2i::default().to_variant()),
            VariantType::Rect2 => init_param::<Rect2>(data, value, property_data, &|| Rect2::default().to_variant()),
            VariantType::Rect2i => init_param::<Rect2i>(data, value, property_data, &|| Rect2i::default().to_variant()),
            VariantType::Vector3 => init_param::<Vector3>(data, value, property_data, &|| Vector3::default().to_variant()),
            VariantType::Vector3i => init_param::<Vector3i>(data, value, property_data, &|| Vector3i::default().to_variant()),
            VariantType::Transform2D => init_param::<Transform2D>(data, value, property_data, &|| Transform2D::default().to_variant()),
            VariantType::Vector4 => init_param::<Vector4>(data, value, property_data, &|| Vector4::default().to_variant()),
            VariantType::Vector4i => init_param::<Vector4i>(data, value, property_data, &|| Vector4i::default().to_variant()),
            VariantType::Plane => init_param::<Plane>(data, value, property_data, &|| Plane::invalid().to_variant()),
            VariantType::Quaternion => init_param::<Quaternion>(data, value, property_data, &|| Quaternion::default().to_variant()),
            VariantType::Aabb => init_param::<Aabb>(data, value, property_data, &|| Aabb::default().to_variant()),
            VariantType::Basis => init_param::<Basis>(data, value, property_data, &|| Basis::default().to_variant()),
            VariantType::Transform3D => init_param::<Transform3D>(data, value, property_data, &|| Transform3D::default().to_variant()),
            VariantType::Projection => init_param::<Projection>(data, value, property_data, &|| Projection::default().to_variant()),
            VariantType::Color => init_param::<Color>(data, value, property_data, &|| Color::default().to_variant()),
            VariantType::StringName => init_param::<StringName>(data, value, property_data, &|| StringName::default().to_variant()),
            VariantType::NodePath => init_param::<NodePath>(data, value, property_data, &|| NodePath::default().to_variant()),
            VariantType::Rid => init_param::<Rid>(data, value, property_data, &|| Rid::new(0).to_variant()),
            VariantType::Object => init_param_variant(data, value, property_data),
            VariantType::Callable => init_param::<Callable>(data, value, property_data, &|| Callable::from_fn("NullFn", |_|{Ok(Variant::nil())}).to_variant()),
            VariantType::Signal => init_param::<Signal>(data, value, property_data, &|| Signal::invalid().to_variant()),
            VariantType::Dictionary => init_param_variant(data, value, property_data),
            VariantType::Array => init_param_variant(data, value, property_data),
            VariantType::PackedByteArray => init_param::<PackedByteArray>(data, value, property_data, &|| PackedByteArray::default().to_variant()),
            VariantType::PackedInt32Array => init_param::<PackedInt32Array>(data, value, property_data, &|| PackedInt32Array::default().to_variant()),
            VariantType::PackedInt64Array => init_param::<PackedInt64Array>(data, value, property_data, &|| PackedInt64Array::default().to_variant()),
            VariantType::PackedFloat32Array => init_param::<PackedFloat32Array>(data, value, property_data, &|| PackedFloat32Array::default().to_variant()),
            VariantType::PackedFloat64Array => init_param::<PackedFloat64Array>(data, value, property_data, &|| PackedFloat64Array::default().to_variant()),
            VariantType::PackedStringArray => init_param::<PackedStringArray>(data, value, property_data, &|| PackedStringArray::default().to_variant()),
            VariantType::PackedVector2Array => init_param::<PackedVector2Array>(data, value, property_data, &|| PackedVector2Array::default().to_variant()),
            VariantType::PackedVector3Array => init_param::<PackedVector3Array>(data, value, property_data, &|| PackedVector3Array::default().to_variant()),
            VariantType::PackedColorArray => init_param::<PackedColorArray>(data, value, property_data, &|| PackedColorArray::default().to_variant()),

            _ => todo!(),
        }

        return true;
    }

    fn on_free(&mut self) {
        let mut base = self.base_mut();
        if !base.has_meta(FREED_BY_ENTITY_TAG.into()) {
            base.cancel_free();
            return;
        }
    }
}
#[godot_api]
impl IObject for _BaseGEComponent {
    fn on_notification(&mut self, what: ObjectNotification) {
        match what {
            ObjectNotification::Predelete => {
                self.on_free()
            },
            _ => {},
        }
    }
    
    fn get_property(&self, property: StringName) -> Option<Variant> {
        Some(self._get_property(property))
    }

    fn set_property(&mut self, property: StringName, v:Variant) -> bool{
        self._set_property(property, v)
    }
}