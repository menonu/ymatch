impl serde::Serialize for ApplyInventoryRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.user_id != 0 {
            len += 1;
        }
        if self.skip_have_decrement {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.ApplyInventoryRequest", len)?;
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        if self.skip_have_decrement {
            struct_ser.serialize_field("skipHaveDecrement", &self.skip_have_decrement)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ApplyInventoryRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "user_id",
            "userId",
            "skip_have_decrement",
            "skipHaveDecrement",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            UserId,
            SkipHaveDecrement,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            "skipHaveDecrement" | "skip_have_decrement" => Ok(GeneratedField::SkipHaveDecrement),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ApplyInventoryRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.ApplyInventoryRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ApplyInventoryRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut user_id__ = None;
                let mut skip_have_decrement__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::SkipHaveDecrement => {
                            if skip_have_decrement__.is_some() {
                                return Err(serde::de::Error::duplicate_field("skipHaveDecrement"));
                            }
                            skip_have_decrement__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(ApplyInventoryRequest {
                    user_id: user_id__.unwrap_or_default(),
                    skip_have_decrement: skip_have_decrement__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.ApplyInventoryRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for BanUserRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.reason.is_some() {
            len += 1;
        }
        if self.banned_until.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.BanUserRequest", len)?;
        if let Some(v) = self.reason.as_ref() {
            struct_ser.serialize_field("reason", v)?;
        }
        if let Some(v) = self.banned_until.as_ref() {
            struct_ser.serialize_field("bannedUntil", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for BanUserRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "reason",
            "banned_until",
            "bannedUntil",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Reason,
            BannedUntil,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "reason" => Ok(GeneratedField::Reason),
                            "bannedUntil" | "banned_until" => Ok(GeneratedField::BannedUntil),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = BanUserRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.BanUserRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<BanUserRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut reason__ = None;
                let mut banned_until__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Reason => {
                            if reason__.is_some() {
                                return Err(serde::de::Error::duplicate_field("reason"));
                            }
                            reason__ = map_.next_value()?;
                        }
                        GeneratedField::BannedUntil => {
                            if banned_until__.is_some() {
                                return Err(serde::de::Error::duplicate_field("bannedUntil"));
                            }
                            banned_until__ = map_.next_value()?;
                        }
                    }
                }
                Ok(BanUserRequest {
                    reason: reason__,
                    banned_until: banned_until__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.BanUserRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for CreateEventRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.name.is_empty() {
            len += 1;
        }
        if self.creator_id != 0 {
            len += 1;
        }
        if self.status.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.CreateEventRequest", len)?;
        if !self.name.is_empty() {
            struct_ser.serialize_field("name", &self.name)?;
        }
        if self.creator_id != 0 {
            struct_ser.serialize_field("creatorId", &self.creator_id)?;
        }
        if let Some(v) = self.status.as_ref() {
            struct_ser.serialize_field("status", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for CreateEventRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "name",
            "creator_id",
            "creatorId",
            "status",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Name,
            CreatorId,
            Status,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "name" => Ok(GeneratedField::Name),
                            "creatorId" | "creator_id" => Ok(GeneratedField::CreatorId),
                            "status" => Ok(GeneratedField::Status),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = CreateEventRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.CreateEventRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<CreateEventRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut name__ = None;
                let mut creator_id__ = None;
                let mut status__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Name => {
                            if name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("name"));
                            }
                            name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::CreatorId => {
                            if creator_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("creatorId"));
                            }
                            creator_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Status => {
                            if status__.is_some() {
                                return Err(serde::de::Error::duplicate_field("status"));
                            }
                            status__ = map_.next_value()?;
                        }
                    }
                }
                Ok(CreateEventRequest {
                    name: name__.unwrap_or_default(),
                    creator_id: creator_id__.unwrap_or_default(),
                    status: status__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.CreateEventRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for CreateGroupRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.event_id != 0 {
            len += 1;
        }
        if self.user_id != 0 {
            len += 1;
        }
        if !self.group_name.is_empty() {
            len += 1;
        }
        if self.description.is_some() {
            len += 1;
        }
        if self.photo_url.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.CreateGroupRequest", len)?;
        if self.event_id != 0 {
            struct_ser.serialize_field("eventId", &self.event_id)?;
        }
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        if !self.group_name.is_empty() {
            struct_ser.serialize_field("groupName", &self.group_name)?;
        }
        if let Some(v) = self.description.as_ref() {
            struct_ser.serialize_field("description", v)?;
        }
        if let Some(v) = self.photo_url.as_ref() {
            struct_ser.serialize_field("photoUrl", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for CreateGroupRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "event_id",
            "eventId",
            "user_id",
            "userId",
            "group_name",
            "groupName",
            "description",
            "photo_url",
            "photoUrl",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            EventId,
            UserId,
            GroupName,
            Description,
            PhotoUrl,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "eventId" | "event_id" => Ok(GeneratedField::EventId),
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            "groupName" | "group_name" => Ok(GeneratedField::GroupName),
                            "description" => Ok(GeneratedField::Description),
                            "photoUrl" | "photo_url" => Ok(GeneratedField::PhotoUrl),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = CreateGroupRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.CreateGroupRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<CreateGroupRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut event_id__ = None;
                let mut user_id__ = None;
                let mut group_name__ = None;
                let mut description__ = None;
                let mut photo_url__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::EventId => {
                            if event_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("eventId"));
                            }
                            event_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::GroupName => {
                            if group_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("groupName"));
                            }
                            group_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Description => {
                            if description__.is_some() {
                                return Err(serde::de::Error::duplicate_field("description"));
                            }
                            description__ = map_.next_value()?;
                        }
                        GeneratedField::PhotoUrl => {
                            if photo_url__.is_some() {
                                return Err(serde::de::Error::duplicate_field("photoUrl"));
                            }
                            photo_url__ = map_.next_value()?;
                        }
                    }
                }
                Ok(CreateGroupRequest {
                    event_id: event_id__.unwrap_or_default(),
                    user_id: user_id__.unwrap_or_default(),
                    group_name: group_name__.unwrap_or_default(),
                    description: description__,
                    photo_url: photo_url__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.CreateGroupRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for CreateMerchRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.name.is_empty() {
            len += 1;
        }
        if self.photo_url.is_some() {
            len += 1;
        }
        if self.group_name.is_some() {
            len += 1;
        }
        if self.creator_id.is_some() {
            len += 1;
        }
        if self.status.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.CreateMerchRequest", len)?;
        if !self.name.is_empty() {
            struct_ser.serialize_field("name", &self.name)?;
        }
        if let Some(v) = self.photo_url.as_ref() {
            struct_ser.serialize_field("photoUrl", v)?;
        }
        if let Some(v) = self.group_name.as_ref() {
            struct_ser.serialize_field("groupName", v)?;
        }
        if let Some(v) = self.creator_id.as_ref() {
            struct_ser.serialize_field("creatorId", v)?;
        }
        if let Some(v) = self.status.as_ref() {
            struct_ser.serialize_field("status", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for CreateMerchRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "name",
            "photo_url",
            "photoUrl",
            "group_name",
            "groupName",
            "creator_id",
            "creatorId",
            "status",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Name,
            PhotoUrl,
            GroupName,
            CreatorId,
            Status,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "name" => Ok(GeneratedField::Name),
                            "photoUrl" | "photo_url" => Ok(GeneratedField::PhotoUrl),
                            "groupName" | "group_name" => Ok(GeneratedField::GroupName),
                            "creatorId" | "creator_id" => Ok(GeneratedField::CreatorId),
                            "status" => Ok(GeneratedField::Status),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = CreateMerchRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.CreateMerchRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<CreateMerchRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut name__ = None;
                let mut photo_url__ = None;
                let mut group_name__ = None;
                let mut creator_id__ = None;
                let mut status__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Name => {
                            if name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("name"));
                            }
                            name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::PhotoUrl => {
                            if photo_url__.is_some() {
                                return Err(serde::de::Error::duplicate_field("photoUrl"));
                            }
                            photo_url__ = map_.next_value()?;
                        }
                        GeneratedField::GroupName => {
                            if group_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("groupName"));
                            }
                            group_name__ = map_.next_value()?;
                        }
                        GeneratedField::CreatorId => {
                            if creator_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("creatorId"));
                            }
                            creator_id__ = 
                                map_.next_value::<::std::option::Option<::pbjson::private::NumberDeserialize<_>>>()?.map(|x| x.0)
                            ;
                        }
                        GeneratedField::Status => {
                            if status__.is_some() {
                                return Err(serde::de::Error::duplicate_field("status"));
                            }
                            status__ = map_.next_value()?;
                        }
                    }
                }
                Ok(CreateMerchRequest {
                    name: name__.unwrap_or_default(),
                    photo_url: photo_url__,
                    group_name: group_name__,
                    creator_id: creator_id__,
                    status: status__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.CreateMerchRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for CreateUserRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.username.is_empty() {
            len += 1;
        }
        if !self.password.is_empty() {
            len += 1;
        }
        if self.device_token.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.CreateUserRequest", len)?;
        if !self.username.is_empty() {
            struct_ser.serialize_field("username", &self.username)?;
        }
        if !self.password.is_empty() {
            struct_ser.serialize_field("password", &self.password)?;
        }
        if let Some(v) = self.device_token.as_ref() {
            struct_ser.serialize_field("deviceToken", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for CreateUserRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "username",
            "password",
            "device_token",
            "deviceToken",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Username,
            Password,
            DeviceToken,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "username" => Ok(GeneratedField::Username),
                            "password" => Ok(GeneratedField::Password),
                            "deviceToken" | "device_token" => Ok(GeneratedField::DeviceToken),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = CreateUserRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.CreateUserRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<CreateUserRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut username__ = None;
                let mut password__ = None;
                let mut device_token__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Username => {
                            if username__.is_some() {
                                return Err(serde::de::Error::duplicate_field("username"));
                            }
                            username__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Password => {
                            if password__.is_some() {
                                return Err(serde::de::Error::duplicate_field("password"));
                            }
                            password__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DeviceToken => {
                            if device_token__.is_some() {
                                return Err(serde::de::Error::duplicate_field("deviceToken"));
                            }
                            device_token__ = map_.next_value()?;
                        }
                    }
                }
                Ok(CreateUserRequest {
                    username: username__.unwrap_or_default(),
                    password: password__.unwrap_or_default(),
                    device_token: device_token__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.CreateUserRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for Event {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.id != 0 {
            len += 1;
        }
        if !self.name.is_empty() {
            len += 1;
        }
        if self.creator_id.is_some() {
            len += 1;
        }
        if self.created_at.is_some() {
            len += 1;
        }
        if self.unique_views.is_some() {
            len += 1;
        }
        if self.active_participants.is_some() {
            len += 1;
        }
        if self.is_favorite.is_some() {
            len += 1;
        }
        if self.is_joined.is_some() {
            len += 1;
        }
        if self.status.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.Event", len)?;
        if self.id != 0 {
            struct_ser.serialize_field("id", &self.id)?;
        }
        if !self.name.is_empty() {
            struct_ser.serialize_field("name", &self.name)?;
        }
        if let Some(v) = self.creator_id.as_ref() {
            struct_ser.serialize_field("creatorId", v)?;
        }
        if let Some(v) = self.created_at.as_ref() {
            struct_ser.serialize_field("createdAt", v)?;
        }
        if let Some(v) = self.unique_views.as_ref() {
            struct_ser.serialize_field("uniqueViews", v)?;
        }
        if let Some(v) = self.active_participants.as_ref() {
            struct_ser.serialize_field("activeParticipants", v)?;
        }
        if let Some(v) = self.is_favorite.as_ref() {
            struct_ser.serialize_field("isFavorite", v)?;
        }
        if let Some(v) = self.is_joined.as_ref() {
            struct_ser.serialize_field("isJoined", v)?;
        }
        if let Some(v) = self.status.as_ref() {
            struct_ser.serialize_field("status", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for Event {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "id",
            "name",
            "creator_id",
            "creatorId",
            "created_at",
            "createdAt",
            "unique_views",
            "uniqueViews",
            "active_participants",
            "activeParticipants",
            "is_favorite",
            "isFavorite",
            "is_joined",
            "isJoined",
            "status",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Id,
            Name,
            CreatorId,
            CreatedAt,
            UniqueViews,
            ActiveParticipants,
            IsFavorite,
            IsJoined,
            Status,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "id" => Ok(GeneratedField::Id),
                            "name" => Ok(GeneratedField::Name),
                            "creatorId" | "creator_id" => Ok(GeneratedField::CreatorId),
                            "createdAt" | "created_at" => Ok(GeneratedField::CreatedAt),
                            "uniqueViews" | "unique_views" => Ok(GeneratedField::UniqueViews),
                            "activeParticipants" | "active_participants" => Ok(GeneratedField::ActiveParticipants),
                            "isFavorite" | "is_favorite" => Ok(GeneratedField::IsFavorite),
                            "isJoined" | "is_joined" => Ok(GeneratedField::IsJoined),
                            "status" => Ok(GeneratedField::Status),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = Event;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.Event")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<Event, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut id__ = None;
                let mut name__ = None;
                let mut creator_id__ = None;
                let mut created_at__ = None;
                let mut unique_views__ = None;
                let mut active_participants__ = None;
                let mut is_favorite__ = None;
                let mut is_joined__ = None;
                let mut status__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Id => {
                            if id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("id"));
                            }
                            id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Name => {
                            if name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("name"));
                            }
                            name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::CreatorId => {
                            if creator_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("creatorId"));
                            }
                            creator_id__ = 
                                map_.next_value::<::std::option::Option<::pbjson::private::NumberDeserialize<_>>>()?.map(|x| x.0)
                            ;
                        }
                        GeneratedField::CreatedAt => {
                            if created_at__.is_some() {
                                return Err(serde::de::Error::duplicate_field("createdAt"));
                            }
                            created_at__ = map_.next_value()?;
                        }
                        GeneratedField::UniqueViews => {
                            if unique_views__.is_some() {
                                return Err(serde::de::Error::duplicate_field("uniqueViews"));
                            }
                            unique_views__ = 
                                map_.next_value::<::std::option::Option<::pbjson::private::NumberDeserialize<_>>>()?.map(|x| x.0)
                            ;
                        }
                        GeneratedField::ActiveParticipants => {
                            if active_participants__.is_some() {
                                return Err(serde::de::Error::duplicate_field("activeParticipants"));
                            }
                            active_participants__ = 
                                map_.next_value::<::std::option::Option<::pbjson::private::NumberDeserialize<_>>>()?.map(|x| x.0)
                            ;
                        }
                        GeneratedField::IsFavorite => {
                            if is_favorite__.is_some() {
                                return Err(serde::de::Error::duplicate_field("isFavorite"));
                            }
                            is_favorite__ = map_.next_value()?;
                        }
                        GeneratedField::IsJoined => {
                            if is_joined__.is_some() {
                                return Err(serde::de::Error::duplicate_field("isJoined"));
                            }
                            is_joined__ = map_.next_value()?;
                        }
                        GeneratedField::Status => {
                            if status__.is_some() {
                                return Err(serde::de::Error::duplicate_field("status"));
                            }
                            status__ = map_.next_value()?;
                        }
                    }
                }
                Ok(Event {
                    id: id__.unwrap_or_default(),
                    name: name__.unwrap_or_default(),
                    creator_id: creator_id__,
                    created_at: created_at__,
                    unique_views: unique_views__,
                    active_participants: active_participants__,
                    is_favorite: is_favorite__,
                    is_joined: is_joined__,
                    status: status__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.Event", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for EventMember {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.user_id != 0 {
            len += 1;
        }
        if !self.role.is_empty() {
            len += 1;
        }
        if self.username.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.EventMember", len)?;
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        if !self.role.is_empty() {
            struct_ser.serialize_field("role", &self.role)?;
        }
        if let Some(v) = self.username.as_ref() {
            struct_ser.serialize_field("username", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for EventMember {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "user_id",
            "userId",
            "role",
            "username",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            UserId,
            Role,
            Username,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            "role" => Ok(GeneratedField::Role),
                            "username" => Ok(GeneratedField::Username),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = EventMember;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.EventMember")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<EventMember, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut user_id__ = None;
                let mut role__ = None;
                let mut username__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Role => {
                            if role__.is_some() {
                                return Err(serde::de::Error::duplicate_field("role"));
                            }
                            role__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Username => {
                            if username__.is_some() {
                                return Err(serde::de::Error::duplicate_field("username"));
                            }
                            username__ = map_.next_value()?;
                        }
                    }
                }
                Ok(EventMember {
                    user_id: user_id__.unwrap_or_default(),
                    role: role__.unwrap_or_default(),
                    username: username__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.EventMember", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for FavoriteGroup {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.user_id != 0 {
            len += 1;
        }
        if self.event_id != 0 {
            len += 1;
        }
        if !self.group_name.is_empty() {
            len += 1;
        }
        if self.event_name.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.FavoriteGroup", len)?;
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        if self.event_id != 0 {
            struct_ser.serialize_field("eventId", &self.event_id)?;
        }
        if !self.group_name.is_empty() {
            struct_ser.serialize_field("groupName", &self.group_name)?;
        }
        if let Some(v) = self.event_name.as_ref() {
            struct_ser.serialize_field("eventName", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for FavoriteGroup {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "user_id",
            "userId",
            "event_id",
            "eventId",
            "group_name",
            "groupName",
            "event_name",
            "eventName",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            UserId,
            EventId,
            GroupName,
            EventName,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            "eventId" | "event_id" => Ok(GeneratedField::EventId),
                            "groupName" | "group_name" => Ok(GeneratedField::GroupName),
                            "eventName" | "event_name" => Ok(GeneratedField::EventName),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = FavoriteGroup;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.FavoriteGroup")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<FavoriteGroup, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut user_id__ = None;
                let mut event_id__ = None;
                let mut group_name__ = None;
                let mut event_name__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::EventId => {
                            if event_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("eventId"));
                            }
                            event_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::GroupName => {
                            if group_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("groupName"));
                            }
                            group_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::EventName => {
                            if event_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("eventName"));
                            }
                            event_name__ = map_.next_value()?;
                        }
                    }
                }
                Ok(FavoriteGroup {
                    user_id: user_id__.unwrap_or_default(),
                    event_id: event_id__.unwrap_or_default(),
                    group_name: group_name__.unwrap_or_default(),
                    event_name: event_name__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.FavoriteGroup", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for GuestLoginRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.uuid.is_empty() {
            len += 1;
        }
        if self.device_token.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.GuestLoginRequest", len)?;
        if !self.uuid.is_empty() {
            struct_ser.serialize_field("uuid", &self.uuid)?;
        }
        if let Some(v) = self.device_token.as_ref() {
            struct_ser.serialize_field("deviceToken", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for GuestLoginRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "uuid",
            "device_token",
            "deviceToken",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Uuid,
            DeviceToken,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "uuid" => Ok(GeneratedField::Uuid),
                            "deviceToken" | "device_token" => Ok(GeneratedField::DeviceToken),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = GuestLoginRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.GuestLoginRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<GuestLoginRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut uuid__ = None;
                let mut device_token__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Uuid => {
                            if uuid__.is_some() {
                                return Err(serde::de::Error::duplicate_field("uuid"));
                            }
                            uuid__ = Some(map_.next_value()?);
                        }
                        GeneratedField::DeviceToken => {
                            if device_token__.is_some() {
                                return Err(serde::de::Error::duplicate_field("deviceToken"));
                            }
                            device_token__ = map_.next_value()?;
                        }
                    }
                }
                Ok(GuestLoginRequest {
                    uuid: uuid__.unwrap_or_default(),
                    device_token: device_token__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.GuestLoginRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for InventoryItem {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.id != 0 {
            len += 1;
        }
        if self.user_id != 0 {
            len += 1;
        }
        if self.merch_id != 0 {
            len += 1;
        }
        if !self.status.is_empty() {
            len += 1;
        }
        if self.quantity != 0 {
            len += 1;
        }
        if self.merch_name.is_some() {
            len += 1;
        }
        if self.photo_url.is_some() {
            len += 1;
        }
        if self.group_name.is_some() {
            len += 1;
        }
        if self.is_deleted.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.InventoryItem", len)?;
        if self.id != 0 {
            struct_ser.serialize_field("id", &self.id)?;
        }
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        if self.merch_id != 0 {
            struct_ser.serialize_field("merchId", &self.merch_id)?;
        }
        if !self.status.is_empty() {
            struct_ser.serialize_field("status", &self.status)?;
        }
        if self.quantity != 0 {
            struct_ser.serialize_field("quantity", &self.quantity)?;
        }
        if let Some(v) = self.merch_name.as_ref() {
            struct_ser.serialize_field("merchName", v)?;
        }
        if let Some(v) = self.photo_url.as_ref() {
            struct_ser.serialize_field("photoUrl", v)?;
        }
        if let Some(v) = self.group_name.as_ref() {
            struct_ser.serialize_field("groupName", v)?;
        }
        if let Some(v) = self.is_deleted.as_ref() {
            struct_ser.serialize_field("isDeleted", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for InventoryItem {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "id",
            "user_id",
            "userId",
            "merch_id",
            "merchId",
            "status",
            "quantity",
            "merch_name",
            "merchName",
            "photo_url",
            "photoUrl",
            "group_name",
            "groupName",
            "is_deleted",
            "isDeleted",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Id,
            UserId,
            MerchId,
            Status,
            Quantity,
            MerchName,
            PhotoUrl,
            GroupName,
            IsDeleted,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "id" => Ok(GeneratedField::Id),
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            "merchId" | "merch_id" => Ok(GeneratedField::MerchId),
                            "status" => Ok(GeneratedField::Status),
                            "quantity" => Ok(GeneratedField::Quantity),
                            "merchName" | "merch_name" => Ok(GeneratedField::MerchName),
                            "photoUrl" | "photo_url" => Ok(GeneratedField::PhotoUrl),
                            "groupName" | "group_name" => Ok(GeneratedField::GroupName),
                            "isDeleted" | "is_deleted" => Ok(GeneratedField::IsDeleted),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = InventoryItem;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.InventoryItem")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<InventoryItem, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut id__ = None;
                let mut user_id__ = None;
                let mut merch_id__ = None;
                let mut status__ = None;
                let mut quantity__ = None;
                let mut merch_name__ = None;
                let mut photo_url__ = None;
                let mut group_name__ = None;
                let mut is_deleted__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Id => {
                            if id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("id"));
                            }
                            id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::MerchId => {
                            if merch_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("merchId"));
                            }
                            merch_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Status => {
                            if status__.is_some() {
                                return Err(serde::de::Error::duplicate_field("status"));
                            }
                            status__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Quantity => {
                            if quantity__.is_some() {
                                return Err(serde::de::Error::duplicate_field("quantity"));
                            }
                            quantity__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::MerchName => {
                            if merch_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("merchName"));
                            }
                            merch_name__ = map_.next_value()?;
                        }
                        GeneratedField::PhotoUrl => {
                            if photo_url__.is_some() {
                                return Err(serde::de::Error::duplicate_field("photoUrl"));
                            }
                            photo_url__ = map_.next_value()?;
                        }
                        GeneratedField::GroupName => {
                            if group_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("groupName"));
                            }
                            group_name__ = map_.next_value()?;
                        }
                        GeneratedField::IsDeleted => {
                            if is_deleted__.is_some() {
                                return Err(serde::de::Error::duplicate_field("isDeleted"));
                            }
                            is_deleted__ = map_.next_value()?;
                        }
                    }
                }
                Ok(InventoryItem {
                    id: id__.unwrap_or_default(),
                    user_id: user_id__.unwrap_or_default(),
                    merch_id: merch_id__.unwrap_or_default(),
                    status: status__.unwrap_or_default(),
                    quantity: quantity__.unwrap_or_default(),
                    merch_name: merch_name__,
                    photo_url: photo_url__,
                    group_name: group_name__,
                    is_deleted: is_deleted__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.InventoryItem", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ListEventMembersResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.members.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.ListEventMembersResponse", len)?;
        if !self.members.is_empty() {
            struct_ser.serialize_field("members", &self.members)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ListEventMembersResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "members",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Members,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "members" => Ok(GeneratedField::Members),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ListEventMembersResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.ListEventMembersResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ListEventMembersResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut members__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Members => {
                            if members__.is_some() {
                                return Err(serde::de::Error::duplicate_field("members"));
                            }
                            members__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(ListEventMembersResponse {
                    members: members__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.ListEventMembersResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ListGroupsResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.groups.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.ListGroupsResponse", len)?;
        if !self.groups.is_empty() {
            struct_ser.serialize_field("groups", &self.groups)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ListGroupsResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "groups",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Groups,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "groups" => Ok(GeneratedField::Groups),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ListGroupsResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.ListGroupsResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ListGroupsResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut groups__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Groups => {
                            if groups__.is_some() {
                                return Err(serde::de::Error::duplicate_field("groups"));
                            }
                            groups__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(ListGroupsResponse {
                    groups: groups__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.ListGroupsResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for LoginRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.username.is_empty() {
            len += 1;
        }
        if !self.password.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.LoginRequest", len)?;
        if !self.username.is_empty() {
            struct_ser.serialize_field("username", &self.username)?;
        }
        if !self.password.is_empty() {
            struct_ser.serialize_field("password", &self.password)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for LoginRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "username",
            "password",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Username,
            Password,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "username" => Ok(GeneratedField::Username),
                            "password" => Ok(GeneratedField::Password),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = LoginRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.LoginRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<LoginRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut username__ = None;
                let mut password__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Username => {
                            if username__.is_some() {
                                return Err(serde::de::Error::duplicate_field("username"));
                            }
                            username__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Password => {
                            if password__.is_some() {
                                return Err(serde::de::Error::duplicate_field("password"));
                            }
                            password__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(LoginRequest {
                    username: username__.unwrap_or_default(),
                    password: password__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.LoginRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for MatchItem {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.id != 0 {
            len += 1;
        }
        if self.match_id != 0 {
            len += 1;
        }
        if self.merch_id != 0 {
            len += 1;
        }
        if self.giver_user_id != 0 {
            len += 1;
        }
        if self.quantity != 0 {
            len += 1;
        }
        if self.merch_name.is_some() {
            len += 1;
        }
        if self.photo_url.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.MatchItem", len)?;
        if self.id != 0 {
            struct_ser.serialize_field("id", &self.id)?;
        }
        if self.match_id != 0 {
            struct_ser.serialize_field("matchId", &self.match_id)?;
        }
        if self.merch_id != 0 {
            struct_ser.serialize_field("merchId", &self.merch_id)?;
        }
        if self.giver_user_id != 0 {
            struct_ser.serialize_field("giverUserId", &self.giver_user_id)?;
        }
        if self.quantity != 0 {
            struct_ser.serialize_field("quantity", &self.quantity)?;
        }
        if let Some(v) = self.merch_name.as_ref() {
            struct_ser.serialize_field("merchName", v)?;
        }
        if let Some(v) = self.photo_url.as_ref() {
            struct_ser.serialize_field("photoUrl", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for MatchItem {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "id",
            "match_id",
            "matchId",
            "merch_id",
            "merchId",
            "giver_user_id",
            "giverUserId",
            "quantity",
            "merch_name",
            "merchName",
            "photo_url",
            "photoUrl",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Id,
            MatchId,
            MerchId,
            GiverUserId,
            Quantity,
            MerchName,
            PhotoUrl,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "id" => Ok(GeneratedField::Id),
                            "matchId" | "match_id" => Ok(GeneratedField::MatchId),
                            "merchId" | "merch_id" => Ok(GeneratedField::MerchId),
                            "giverUserId" | "giver_user_id" => Ok(GeneratedField::GiverUserId),
                            "quantity" => Ok(GeneratedField::Quantity),
                            "merchName" | "merch_name" => Ok(GeneratedField::MerchName),
                            "photoUrl" | "photo_url" => Ok(GeneratedField::PhotoUrl),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = MatchItem;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.MatchItem")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<MatchItem, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut id__ = None;
                let mut match_id__ = None;
                let mut merch_id__ = None;
                let mut giver_user_id__ = None;
                let mut quantity__ = None;
                let mut merch_name__ = None;
                let mut photo_url__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Id => {
                            if id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("id"));
                            }
                            id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::MatchId => {
                            if match_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("matchId"));
                            }
                            match_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::MerchId => {
                            if merch_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("merchId"));
                            }
                            merch_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::GiverUserId => {
                            if giver_user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("giverUserId"));
                            }
                            giver_user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Quantity => {
                            if quantity__.is_some() {
                                return Err(serde::de::Error::duplicate_field("quantity"));
                            }
                            quantity__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::MerchName => {
                            if merch_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("merchName"));
                            }
                            merch_name__ = map_.next_value()?;
                        }
                        GeneratedField::PhotoUrl => {
                            if photo_url__.is_some() {
                                return Err(serde::de::Error::duplicate_field("photoUrl"));
                            }
                            photo_url__ = map_.next_value()?;
                        }
                    }
                }
                Ok(MatchItem {
                    id: id__.unwrap_or_default(),
                    match_id: match_id__.unwrap_or_default(),
                    merch_id: merch_id__.unwrap_or_default(),
                    giver_user_id: giver_user_id__.unwrap_or_default(),
                    quantity: quantity__.unwrap_or_default(),
                    merch_name: merch_name__,
                    photo_url: photo_url__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.MatchItem", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for Merchandise {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.id != 0 {
            len += 1;
        }
        if self.event_id != 0 {
            len += 1;
        }
        if !self.name.is_empty() {
            len += 1;
        }
        if self.photo_url.is_some() {
            len += 1;
        }
        if self.group_name.is_some() {
            len += 1;
        }
        if self.status.is_some() {
            len += 1;
        }
        if self.is_deleted.is_some() {
            len += 1;
        }
        if self.trade_enabled.is_some() {
            len += 1;
        }
        if self.creator_id.is_some() {
            len += 1;
        }
        if self.group_description.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.Merchandise", len)?;
        if self.id != 0 {
            struct_ser.serialize_field("id", &self.id)?;
        }
        if self.event_id != 0 {
            struct_ser.serialize_field("eventId", &self.event_id)?;
        }
        if !self.name.is_empty() {
            struct_ser.serialize_field("name", &self.name)?;
        }
        if let Some(v) = self.photo_url.as_ref() {
            struct_ser.serialize_field("photoUrl", v)?;
        }
        if let Some(v) = self.group_name.as_ref() {
            struct_ser.serialize_field("groupName", v)?;
        }
        if let Some(v) = self.status.as_ref() {
            struct_ser.serialize_field("status", v)?;
        }
        if let Some(v) = self.is_deleted.as_ref() {
            struct_ser.serialize_field("isDeleted", v)?;
        }
        if let Some(v) = self.trade_enabled.as_ref() {
            struct_ser.serialize_field("tradeEnabled", v)?;
        }
        if let Some(v) = self.creator_id.as_ref() {
            struct_ser.serialize_field("creatorId", v)?;
        }
        if let Some(v) = self.group_description.as_ref() {
            struct_ser.serialize_field("groupDescription", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for Merchandise {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "id",
            "event_id",
            "eventId",
            "name",
            "photo_url",
            "photoUrl",
            "group_name",
            "groupName",
            "status",
            "is_deleted",
            "isDeleted",
            "trade_enabled",
            "tradeEnabled",
            "creator_id",
            "creatorId",
            "group_description",
            "groupDescription",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Id,
            EventId,
            Name,
            PhotoUrl,
            GroupName,
            Status,
            IsDeleted,
            TradeEnabled,
            CreatorId,
            GroupDescription,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "id" => Ok(GeneratedField::Id),
                            "eventId" | "event_id" => Ok(GeneratedField::EventId),
                            "name" => Ok(GeneratedField::Name),
                            "photoUrl" | "photo_url" => Ok(GeneratedField::PhotoUrl),
                            "groupName" | "group_name" => Ok(GeneratedField::GroupName),
                            "status" => Ok(GeneratedField::Status),
                            "isDeleted" | "is_deleted" => Ok(GeneratedField::IsDeleted),
                            "tradeEnabled" | "trade_enabled" => Ok(GeneratedField::TradeEnabled),
                            "creatorId" | "creator_id" => Ok(GeneratedField::CreatorId),
                            "groupDescription" | "group_description" => Ok(GeneratedField::GroupDescription),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = Merchandise;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.Merchandise")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<Merchandise, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut id__ = None;
                let mut event_id__ = None;
                let mut name__ = None;
                let mut photo_url__ = None;
                let mut group_name__ = None;
                let mut status__ = None;
                let mut is_deleted__ = None;
                let mut trade_enabled__ = None;
                let mut creator_id__ = None;
                let mut group_description__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Id => {
                            if id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("id"));
                            }
                            id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::EventId => {
                            if event_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("eventId"));
                            }
                            event_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Name => {
                            if name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("name"));
                            }
                            name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::PhotoUrl => {
                            if photo_url__.is_some() {
                                return Err(serde::de::Error::duplicate_field("photoUrl"));
                            }
                            photo_url__ = map_.next_value()?;
                        }
                        GeneratedField::GroupName => {
                            if group_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("groupName"));
                            }
                            group_name__ = map_.next_value()?;
                        }
                        GeneratedField::Status => {
                            if status__.is_some() {
                                return Err(serde::de::Error::duplicate_field("status"));
                            }
                            status__ = map_.next_value()?;
                        }
                        GeneratedField::IsDeleted => {
                            if is_deleted__.is_some() {
                                return Err(serde::de::Error::duplicate_field("isDeleted"));
                            }
                            is_deleted__ = map_.next_value()?;
                        }
                        GeneratedField::TradeEnabled => {
                            if trade_enabled__.is_some() {
                                return Err(serde::de::Error::duplicate_field("tradeEnabled"));
                            }
                            trade_enabled__ = map_.next_value()?;
                        }
                        GeneratedField::CreatorId => {
                            if creator_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("creatorId"));
                            }
                            creator_id__ = 
                                map_.next_value::<::std::option::Option<::pbjson::private::NumberDeserialize<_>>>()?.map(|x| x.0)
                            ;
                        }
                        GeneratedField::GroupDescription => {
                            if group_description__.is_some() {
                                return Err(serde::de::Error::duplicate_field("groupDescription"));
                            }
                            group_description__ = map_.next_value()?;
                        }
                    }
                }
                Ok(Merchandise {
                    id: id__.unwrap_or_default(),
                    event_id: event_id__.unwrap_or_default(),
                    name: name__.unwrap_or_default(),
                    photo_url: photo_url__,
                    group_name: group_name__,
                    status: status__,
                    is_deleted: is_deleted__,
                    trade_enabled: trade_enabled__,
                    creator_id: creator_id__,
                    group_description: group_description__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.Merchandise", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for MerchandiseGroup {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.id != 0 {
            len += 1;
        }
        if self.event_id != 0 {
            len += 1;
        }
        if !self.group_name.is_empty() {
            len += 1;
        }
        if self.description.is_some() {
            len += 1;
        }
        if self.created_by.is_some() {
            len += 1;
        }
        if self.created_at.is_some() {
            len += 1;
        }
        if self.updated_at.is_some() {
            len += 1;
        }
        if self.photo_url.is_some() {
            len += 1;
        }
        if self.display_name.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.MerchandiseGroup", len)?;
        if self.id != 0 {
            struct_ser.serialize_field("id", &self.id)?;
        }
        if self.event_id != 0 {
            struct_ser.serialize_field("eventId", &self.event_id)?;
        }
        if !self.group_name.is_empty() {
            struct_ser.serialize_field("groupName", &self.group_name)?;
        }
        if let Some(v) = self.description.as_ref() {
            struct_ser.serialize_field("description", v)?;
        }
        if let Some(v) = self.created_by.as_ref() {
            struct_ser.serialize_field("createdBy", v)?;
        }
        if let Some(v) = self.created_at.as_ref() {
            struct_ser.serialize_field("createdAt", v)?;
        }
        if let Some(v) = self.updated_at.as_ref() {
            struct_ser.serialize_field("updatedAt", v)?;
        }
        if let Some(v) = self.photo_url.as_ref() {
            struct_ser.serialize_field("photoUrl", v)?;
        }
        if let Some(v) = self.display_name.as_ref() {
            struct_ser.serialize_field("displayName", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for MerchandiseGroup {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "id",
            "event_id",
            "eventId",
            "group_name",
            "groupName",
            "description",
            "created_by",
            "createdBy",
            "created_at",
            "createdAt",
            "updated_at",
            "updatedAt",
            "photo_url",
            "photoUrl",
            "display_name",
            "displayName",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Id,
            EventId,
            GroupName,
            Description,
            CreatedBy,
            CreatedAt,
            UpdatedAt,
            PhotoUrl,
            DisplayName,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "id" => Ok(GeneratedField::Id),
                            "eventId" | "event_id" => Ok(GeneratedField::EventId),
                            "groupName" | "group_name" => Ok(GeneratedField::GroupName),
                            "description" => Ok(GeneratedField::Description),
                            "createdBy" | "created_by" => Ok(GeneratedField::CreatedBy),
                            "createdAt" | "created_at" => Ok(GeneratedField::CreatedAt),
                            "updatedAt" | "updated_at" => Ok(GeneratedField::UpdatedAt),
                            "photoUrl" | "photo_url" => Ok(GeneratedField::PhotoUrl),
                            "displayName" | "display_name" => Ok(GeneratedField::DisplayName),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = MerchandiseGroup;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.MerchandiseGroup")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<MerchandiseGroup, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut id__ = None;
                let mut event_id__ = None;
                let mut group_name__ = None;
                let mut description__ = None;
                let mut created_by__ = None;
                let mut created_at__ = None;
                let mut updated_at__ = None;
                let mut photo_url__ = None;
                let mut display_name__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Id => {
                            if id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("id"));
                            }
                            id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::EventId => {
                            if event_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("eventId"));
                            }
                            event_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::GroupName => {
                            if group_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("groupName"));
                            }
                            group_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Description => {
                            if description__.is_some() {
                                return Err(serde::de::Error::duplicate_field("description"));
                            }
                            description__ = map_.next_value()?;
                        }
                        GeneratedField::CreatedBy => {
                            if created_by__.is_some() {
                                return Err(serde::de::Error::duplicate_field("createdBy"));
                            }
                            created_by__ = 
                                map_.next_value::<::std::option::Option<::pbjson::private::NumberDeserialize<_>>>()?.map(|x| x.0)
                            ;
                        }
                        GeneratedField::CreatedAt => {
                            if created_at__.is_some() {
                                return Err(serde::de::Error::duplicate_field("createdAt"));
                            }
                            created_at__ = map_.next_value()?;
                        }
                        GeneratedField::UpdatedAt => {
                            if updated_at__.is_some() {
                                return Err(serde::de::Error::duplicate_field("updatedAt"));
                            }
                            updated_at__ = map_.next_value()?;
                        }
                        GeneratedField::PhotoUrl => {
                            if photo_url__.is_some() {
                                return Err(serde::de::Error::duplicate_field("photoUrl"));
                            }
                            photo_url__ = map_.next_value()?;
                        }
                        GeneratedField::DisplayName => {
                            if display_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("displayName"));
                            }
                            display_name__ = map_.next_value()?;
                        }
                    }
                }
                Ok(MerchandiseGroup {
                    id: id__.unwrap_or_default(),
                    event_id: event_id__.unwrap_or_default(),
                    group_name: group_name__.unwrap_or_default(),
                    description: description__,
                    created_by: created_by__,
                    created_at: created_at__,
                    updated_at: updated_at__,
                    photo_url: photo_url__,
                    display_name: display_name__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.MerchandiseGroup", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for Message {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.id != 0 {
            len += 1;
        }
        if self.match_id != 0 {
            len += 1;
        }
        if self.sender_id != 0 {
            len += 1;
        }
        if !self.content.is_empty() {
            len += 1;
        }
        if self.created_at.is_some() {
            len += 1;
        }
        if self.message_type.is_some() {
            len += 1;
        }
        if self.latitude.is_some() {
            len += 1;
        }
        if self.longitude.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.Message", len)?;
        if self.id != 0 {
            struct_ser.serialize_field("id", &self.id)?;
        }
        if self.match_id != 0 {
            struct_ser.serialize_field("matchId", &self.match_id)?;
        }
        if self.sender_id != 0 {
            struct_ser.serialize_field("senderId", &self.sender_id)?;
        }
        if !self.content.is_empty() {
            struct_ser.serialize_field("content", &self.content)?;
        }
        if let Some(v) = self.created_at.as_ref() {
            struct_ser.serialize_field("createdAt", v)?;
        }
        if let Some(v) = self.message_type.as_ref() {
            struct_ser.serialize_field("messageType", v)?;
        }
        if let Some(v) = self.latitude.as_ref() {
            struct_ser.serialize_field("latitude", v)?;
        }
        if let Some(v) = self.longitude.as_ref() {
            struct_ser.serialize_field("longitude", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for Message {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "id",
            "match_id",
            "matchId",
            "sender_id",
            "senderId",
            "content",
            "created_at",
            "createdAt",
            "message_type",
            "messageType",
            "latitude",
            "longitude",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Id,
            MatchId,
            SenderId,
            Content,
            CreatedAt,
            MessageType,
            Latitude,
            Longitude,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "id" => Ok(GeneratedField::Id),
                            "matchId" | "match_id" => Ok(GeneratedField::MatchId),
                            "senderId" | "sender_id" => Ok(GeneratedField::SenderId),
                            "content" => Ok(GeneratedField::Content),
                            "createdAt" | "created_at" => Ok(GeneratedField::CreatedAt),
                            "messageType" | "message_type" => Ok(GeneratedField::MessageType),
                            "latitude" => Ok(GeneratedField::Latitude),
                            "longitude" => Ok(GeneratedField::Longitude),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = Message;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.Message")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<Message, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut id__ = None;
                let mut match_id__ = None;
                let mut sender_id__ = None;
                let mut content__ = None;
                let mut created_at__ = None;
                let mut message_type__ = None;
                let mut latitude__ = None;
                let mut longitude__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Id => {
                            if id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("id"));
                            }
                            id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::MatchId => {
                            if match_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("matchId"));
                            }
                            match_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::SenderId => {
                            if sender_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("senderId"));
                            }
                            sender_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Content => {
                            if content__.is_some() {
                                return Err(serde::de::Error::duplicate_field("content"));
                            }
                            content__ = Some(map_.next_value()?);
                        }
                        GeneratedField::CreatedAt => {
                            if created_at__.is_some() {
                                return Err(serde::de::Error::duplicate_field("createdAt"));
                            }
                            created_at__ = map_.next_value()?;
                        }
                        GeneratedField::MessageType => {
                            if message_type__.is_some() {
                                return Err(serde::de::Error::duplicate_field("messageType"));
                            }
                            message_type__ = map_.next_value()?;
                        }
                        GeneratedField::Latitude => {
                            if latitude__.is_some() {
                                return Err(serde::de::Error::duplicate_field("latitude"));
                            }
                            latitude__ = 
                                map_.next_value::<::std::option::Option<::pbjson::private::NumberDeserialize<_>>>()?.map(|x| x.0)
                            ;
                        }
                        GeneratedField::Longitude => {
                            if longitude__.is_some() {
                                return Err(serde::de::Error::duplicate_field("longitude"));
                            }
                            longitude__ = 
                                map_.next_value::<::std::option::Option<::pbjson::private::NumberDeserialize<_>>>()?.map(|x| x.0)
                            ;
                        }
                    }
                }
                Ok(Message {
                    id: id__.unwrap_or_default(),
                    match_id: match_id__.unwrap_or_default(),
                    sender_id: sender_id__.unwrap_or_default(),
                    content: content__.unwrap_or_default(),
                    created_at: created_at__,
                    message_type: message_type__,
                    latitude: latitude__,
                    longitude: longitude__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.Message", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for MyEventRoleResponse {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.role.is_empty() {
            len += 1;
        }
        if self.global_override {
            len += 1;
        }
        if self.can_create_merch {
            len += 1;
        }
        if self.can_edit_group {
            len += 1;
        }
        if self.can_manage_editors {
            len += 1;
        }
        if self.can_transfer_creator {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.MyEventRoleResponse", len)?;
        if !self.role.is_empty() {
            struct_ser.serialize_field("role", &self.role)?;
        }
        if self.global_override {
            struct_ser.serialize_field("globalOverride", &self.global_override)?;
        }
        if self.can_create_merch {
            struct_ser.serialize_field("canCreateMerch", &self.can_create_merch)?;
        }
        if self.can_edit_group {
            struct_ser.serialize_field("canEditGroup", &self.can_edit_group)?;
        }
        if self.can_manage_editors {
            struct_ser.serialize_field("canManageEditors", &self.can_manage_editors)?;
        }
        if self.can_transfer_creator {
            struct_ser.serialize_field("canTransferCreator", &self.can_transfer_creator)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for MyEventRoleResponse {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "role",
            "global_override",
            "globalOverride",
            "can_create_merch",
            "canCreateMerch",
            "can_edit_group",
            "canEditGroup",
            "can_manage_editors",
            "canManageEditors",
            "can_transfer_creator",
            "canTransferCreator",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Role,
            GlobalOverride,
            CanCreateMerch,
            CanEditGroup,
            CanManageEditors,
            CanTransferCreator,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "role" => Ok(GeneratedField::Role),
                            "globalOverride" | "global_override" => Ok(GeneratedField::GlobalOverride),
                            "canCreateMerch" | "can_create_merch" => Ok(GeneratedField::CanCreateMerch),
                            "canEditGroup" | "can_edit_group" => Ok(GeneratedField::CanEditGroup),
                            "canManageEditors" | "can_manage_editors" => Ok(GeneratedField::CanManageEditors),
                            "canTransferCreator" | "can_transfer_creator" => Ok(GeneratedField::CanTransferCreator),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = MyEventRoleResponse;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.MyEventRoleResponse")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<MyEventRoleResponse, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut role__ = None;
                let mut global_override__ = None;
                let mut can_create_merch__ = None;
                let mut can_edit_group__ = None;
                let mut can_manage_editors__ = None;
                let mut can_transfer_creator__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Role => {
                            if role__.is_some() {
                                return Err(serde::de::Error::duplicate_field("role"));
                            }
                            role__ = Some(map_.next_value()?);
                        }
                        GeneratedField::GlobalOverride => {
                            if global_override__.is_some() {
                                return Err(serde::de::Error::duplicate_field("globalOverride"));
                            }
                            global_override__ = Some(map_.next_value()?);
                        }
                        GeneratedField::CanCreateMerch => {
                            if can_create_merch__.is_some() {
                                return Err(serde::de::Error::duplicate_field("canCreateMerch"));
                            }
                            can_create_merch__ = Some(map_.next_value()?);
                        }
                        GeneratedField::CanEditGroup => {
                            if can_edit_group__.is_some() {
                                return Err(serde::de::Error::duplicate_field("canEditGroup"));
                            }
                            can_edit_group__ = Some(map_.next_value()?);
                        }
                        GeneratedField::CanManageEditors => {
                            if can_manage_editors__.is_some() {
                                return Err(serde::de::Error::duplicate_field("canManageEditors"));
                            }
                            can_manage_editors__ = Some(map_.next_value()?);
                        }
                        GeneratedField::CanTransferCreator => {
                            if can_transfer_creator__.is_some() {
                                return Err(serde::de::Error::duplicate_field("canTransferCreator"));
                            }
                            can_transfer_creator__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(MyEventRoleResponse {
                    role: role__.unwrap_or_default(),
                    global_override: global_override__.unwrap_or_default(),
                    can_create_merch: can_create_merch__.unwrap_or_default(),
                    can_edit_group: can_edit_group__.unwrap_or_default(),
                    can_manage_editors: can_manage_editors__.unwrap_or_default(),
                    can_transfer_creator: can_transfer_creator__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.MyEventRoleResponse", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for NotificationCounts {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.pending_matches != 0 {
            len += 1;
        }
        if self.offers_in != 0 {
            len += 1;
        }
        if self.accepted != 0 {
            len += 1;
        }
        if self.unread_messages != 0 {
            len += 1;
        }
        if self.total != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.NotificationCounts", len)?;
        if self.pending_matches != 0 {
            struct_ser.serialize_field("pendingMatches", &self.pending_matches)?;
        }
        if self.offers_in != 0 {
            struct_ser.serialize_field("offersIn", &self.offers_in)?;
        }
        if self.accepted != 0 {
            struct_ser.serialize_field("accepted", &self.accepted)?;
        }
        if self.unread_messages != 0 {
            struct_ser.serialize_field("unreadMessages", &self.unread_messages)?;
        }
        if self.total != 0 {
            struct_ser.serialize_field("total", &self.total)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for NotificationCounts {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "pending_matches",
            "pendingMatches",
            "offers_in",
            "offersIn",
            "accepted",
            "unread_messages",
            "unreadMessages",
            "total",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            PendingMatches,
            OffersIn,
            Accepted,
            UnreadMessages,
            Total,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "pendingMatches" | "pending_matches" => Ok(GeneratedField::PendingMatches),
                            "offersIn" | "offers_in" => Ok(GeneratedField::OffersIn),
                            "accepted" => Ok(GeneratedField::Accepted),
                            "unreadMessages" | "unread_messages" => Ok(GeneratedField::UnreadMessages),
                            "total" => Ok(GeneratedField::Total),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = NotificationCounts;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.NotificationCounts")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<NotificationCounts, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut pending_matches__ = None;
                let mut offers_in__ = None;
                let mut accepted__ = None;
                let mut unread_messages__ = None;
                let mut total__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::PendingMatches => {
                            if pending_matches__.is_some() {
                                return Err(serde::de::Error::duplicate_field("pendingMatches"));
                            }
                            pending_matches__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::OffersIn => {
                            if offers_in__.is_some() {
                                return Err(serde::de::Error::duplicate_field("offersIn"));
                            }
                            offers_in__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Accepted => {
                            if accepted__.is_some() {
                                return Err(serde::de::Error::duplicate_field("accepted"));
                            }
                            accepted__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::UnreadMessages => {
                            if unread_messages__.is_some() {
                                return Err(serde::de::Error::duplicate_field("unreadMessages"));
                            }
                            unread_messages__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Total => {
                            if total__.is_some() {
                                return Err(serde::de::Error::duplicate_field("total"));
                            }
                            total__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(NotificationCounts {
                    pending_matches: pending_matches__.unwrap_or_default(),
                    offers_in: offers_in__.unwrap_or_default(),
                    accepted: accepted__.unwrap_or_default(),
                    unread_messages: unread_messages__.unwrap_or_default(),
                    total: total__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.NotificationCounts", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for OfferItem {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.merch_id != 0 {
            len += 1;
        }
        if self.giver_user_id != 0 {
            len += 1;
        }
        if self.quantity != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.OfferItem", len)?;
        if self.merch_id != 0 {
            struct_ser.serialize_field("merchId", &self.merch_id)?;
        }
        if self.giver_user_id != 0 {
            struct_ser.serialize_field("giverUserId", &self.giver_user_id)?;
        }
        if self.quantity != 0 {
            struct_ser.serialize_field("quantity", &self.quantity)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for OfferItem {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "merch_id",
            "merchId",
            "giver_user_id",
            "giverUserId",
            "quantity",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            MerchId,
            GiverUserId,
            Quantity,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "merchId" | "merch_id" => Ok(GeneratedField::MerchId),
                            "giverUserId" | "giver_user_id" => Ok(GeneratedField::GiverUserId),
                            "quantity" => Ok(GeneratedField::Quantity),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = OfferItem;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.OfferItem")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<OfferItem, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut merch_id__ = None;
                let mut giver_user_id__ = None;
                let mut quantity__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::MerchId => {
                            if merch_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("merchId"));
                            }
                            merch_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::GiverUserId => {
                            if giver_user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("giverUserId"));
                            }
                            giver_user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Quantity => {
                            if quantity__.is_some() {
                                return Err(serde::de::Error::duplicate_field("quantity"));
                            }
                            quantity__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(OfferItem {
                    merch_id: merch_id__.unwrap_or_default(),
                    giver_user_id: giver_user_id__.unwrap_or_default(),
                    quantity: quantity__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.OfferItem", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for OfferTradeRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.user_id != 0 {
            len += 1;
        }
        if !self.items.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.OfferTradeRequest", len)?;
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        if !self.items.is_empty() {
            struct_ser.serialize_field("items", &self.items)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for OfferTradeRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "user_id",
            "userId",
            "items",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            UserId,
            Items,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            "items" => Ok(GeneratedField::Items),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = OfferTradeRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.OfferTradeRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<OfferTradeRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut user_id__ = None;
                let mut items__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Items => {
                            if items__.is_some() {
                                return Err(serde::de::Error::duplicate_field("items"));
                            }
                            items__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(OfferTradeRequest {
                    user_id: user_id__.unwrap_or_default(),
                    items: items__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.OfferTradeRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for SearchResult {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.r#type.is_empty() {
            len += 1;
        }
        if self.id != 0 {
            len += 1;
        }
        if !self.title.is_empty() {
            len += 1;
        }
        if self.subtitle.is_some() {
            len += 1;
        }
        if self.photo_url.is_some() {
            len += 1;
        }
        if self.event_id != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.SearchResult", len)?;
        if !self.r#type.is_empty() {
            struct_ser.serialize_field("type", &self.r#type)?;
        }
        if self.id != 0 {
            struct_ser.serialize_field("id", &self.id)?;
        }
        if !self.title.is_empty() {
            struct_ser.serialize_field("title", &self.title)?;
        }
        if let Some(v) = self.subtitle.as_ref() {
            struct_ser.serialize_field("subtitle", v)?;
        }
        if let Some(v) = self.photo_url.as_ref() {
            struct_ser.serialize_field("photoUrl", v)?;
        }
        if self.event_id != 0 {
            struct_ser.serialize_field("eventId", &self.event_id)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for SearchResult {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "type",
            "id",
            "title",
            "subtitle",
            "photo_url",
            "photoUrl",
            "event_id",
            "eventId",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Type,
            Id,
            Title,
            Subtitle,
            PhotoUrl,
            EventId,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "type" => Ok(GeneratedField::Type),
                            "id" => Ok(GeneratedField::Id),
                            "title" => Ok(GeneratedField::Title),
                            "subtitle" => Ok(GeneratedField::Subtitle),
                            "photoUrl" | "photo_url" => Ok(GeneratedField::PhotoUrl),
                            "eventId" | "event_id" => Ok(GeneratedField::EventId),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = SearchResult;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.SearchResult")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<SearchResult, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut r#type__ = None;
                let mut id__ = None;
                let mut title__ = None;
                let mut subtitle__ = None;
                let mut photo_url__ = None;
                let mut event_id__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Type => {
                            if r#type__.is_some() {
                                return Err(serde::de::Error::duplicate_field("type"));
                            }
                            r#type__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Id => {
                            if id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("id"));
                            }
                            id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Title => {
                            if title__.is_some() {
                                return Err(serde::de::Error::duplicate_field("title"));
                            }
                            title__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Subtitle => {
                            if subtitle__.is_some() {
                                return Err(serde::de::Error::duplicate_field("subtitle"));
                            }
                            subtitle__ = map_.next_value()?;
                        }
                        GeneratedField::PhotoUrl => {
                            if photo_url__.is_some() {
                                return Err(serde::de::Error::duplicate_field("photoUrl"));
                            }
                            photo_url__ = map_.next_value()?;
                        }
                        GeneratedField::EventId => {
                            if event_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("eventId"));
                            }
                            event_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(SearchResult {
                    r#type: r#type__.unwrap_or_default(),
                    id: id__.unwrap_or_default(),
                    title: title__.unwrap_or_default(),
                    subtitle: subtitle__,
                    photo_url: photo_url__,
                    event_id: event_id__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.SearchResult", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for SendMessageRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.match_id != 0 {
            len += 1;
        }
        if self.sender_id != 0 {
            len += 1;
        }
        if !self.content.is_empty() {
            len += 1;
        }
        if self.message_type.is_some() {
            len += 1;
        }
        if self.latitude.is_some() {
            len += 1;
        }
        if self.longitude.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.SendMessageRequest", len)?;
        if self.match_id != 0 {
            struct_ser.serialize_field("matchId", &self.match_id)?;
        }
        if self.sender_id != 0 {
            struct_ser.serialize_field("senderId", &self.sender_id)?;
        }
        if !self.content.is_empty() {
            struct_ser.serialize_field("content", &self.content)?;
        }
        if let Some(v) = self.message_type.as_ref() {
            struct_ser.serialize_field("messageType", v)?;
        }
        if let Some(v) = self.latitude.as_ref() {
            struct_ser.serialize_field("latitude", v)?;
        }
        if let Some(v) = self.longitude.as_ref() {
            struct_ser.serialize_field("longitude", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for SendMessageRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "match_id",
            "matchId",
            "sender_id",
            "senderId",
            "content",
            "message_type",
            "messageType",
            "latitude",
            "longitude",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            MatchId,
            SenderId,
            Content,
            MessageType,
            Latitude,
            Longitude,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "matchId" | "match_id" => Ok(GeneratedField::MatchId),
                            "senderId" | "sender_id" => Ok(GeneratedField::SenderId),
                            "content" => Ok(GeneratedField::Content),
                            "messageType" | "message_type" => Ok(GeneratedField::MessageType),
                            "latitude" => Ok(GeneratedField::Latitude),
                            "longitude" => Ok(GeneratedField::Longitude),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = SendMessageRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.SendMessageRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<SendMessageRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut match_id__ = None;
                let mut sender_id__ = None;
                let mut content__ = None;
                let mut message_type__ = None;
                let mut latitude__ = None;
                let mut longitude__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::MatchId => {
                            if match_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("matchId"));
                            }
                            match_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::SenderId => {
                            if sender_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("senderId"));
                            }
                            sender_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Content => {
                            if content__.is_some() {
                                return Err(serde::de::Error::duplicate_field("content"));
                            }
                            content__ = Some(map_.next_value()?);
                        }
                        GeneratedField::MessageType => {
                            if message_type__.is_some() {
                                return Err(serde::de::Error::duplicate_field("messageType"));
                            }
                            message_type__ = map_.next_value()?;
                        }
                        GeneratedField::Latitude => {
                            if latitude__.is_some() {
                                return Err(serde::de::Error::duplicate_field("latitude"));
                            }
                            latitude__ = 
                                map_.next_value::<::std::option::Option<::pbjson::private::NumberDeserialize<_>>>()?.map(|x| x.0)
                            ;
                        }
                        GeneratedField::Longitude => {
                            if longitude__.is_some() {
                                return Err(serde::de::Error::duplicate_field("longitude"));
                            }
                            longitude__ = 
                                map_.next_value::<::std::option::Option<::pbjson::private::NumberDeserialize<_>>>()?.map(|x| x.0)
                            ;
                        }
                    }
                }
                Ok(SendMessageRequest {
                    match_id: match_id__.unwrap_or_default(),
                    sender_id: sender_id__.unwrap_or_default(),
                    content: content__.unwrap_or_default(),
                    message_type: message_type__,
                    latitude: latitude__,
                    longitude: longitude__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.SendMessageRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ToggleFavoriteGroupRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.user_id != 0 {
            len += 1;
        }
        if !self.group_name.is_empty() {
            len += 1;
        }
        if self.is_favorite {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.ToggleFavoriteGroupRequest", len)?;
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        if !self.group_name.is_empty() {
            struct_ser.serialize_field("groupName", &self.group_name)?;
        }
        if self.is_favorite {
            struct_ser.serialize_field("isFavorite", &self.is_favorite)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ToggleFavoriteGroupRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "user_id",
            "userId",
            "group_name",
            "groupName",
            "is_favorite",
            "isFavorite",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            UserId,
            GroupName,
            IsFavorite,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            "groupName" | "group_name" => Ok(GeneratedField::GroupName),
                            "isFavorite" | "is_favorite" => Ok(GeneratedField::IsFavorite),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ToggleFavoriteGroupRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.ToggleFavoriteGroupRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ToggleFavoriteGroupRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut user_id__ = None;
                let mut group_name__ = None;
                let mut is_favorite__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::GroupName => {
                            if group_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("groupName"));
                            }
                            group_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::IsFavorite => {
                            if is_favorite__.is_some() {
                                return Err(serde::de::Error::duplicate_field("isFavorite"));
                            }
                            is_favorite__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(ToggleFavoriteGroupRequest {
                    user_id: user_id__.unwrap_or_default(),
                    group_name: group_name__.unwrap_or_default(),
                    is_favorite: is_favorite__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.ToggleFavoriteGroupRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for ToggleFavoriteRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.user_id != 0 {
            len += 1;
        }
        if self.is_favorite {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.ToggleFavoriteRequest", len)?;
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        if self.is_favorite {
            struct_ser.serialize_field("isFavorite", &self.is_favorite)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for ToggleFavoriteRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "user_id",
            "userId",
            "is_favorite",
            "isFavorite",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            UserId,
            IsFavorite,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            "isFavorite" | "is_favorite" => Ok(GeneratedField::IsFavorite),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = ToggleFavoriteRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.ToggleFavoriteRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<ToggleFavoriteRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut user_id__ = None;
                let mut is_favorite__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::IsFavorite => {
                            if is_favorite__.is_some() {
                                return Err(serde::de::Error::duplicate_field("isFavorite"));
                            }
                            is_favorite__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(ToggleFavoriteRequest {
                    user_id: user_id__.unwrap_or_default(),
                    is_favorite: is_favorite__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.ToggleFavoriteRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for TradeMatch {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.id != 0 {
            len += 1;
        }
        if self.user1_id != 0 {
            len += 1;
        }
        if self.user2_id != 0 {
            len += 1;
        }
        if !self.status.is_empty() {
            len += 1;
        }
        if self.created_at.is_some() {
            len += 1;
        }
        if self.other_user.is_some() {
            len += 1;
        }
        if !self.user_haves.is_empty() {
            len += 1;
        }
        if !self.user_wants.is_empty() {
            len += 1;
        }
        if self.offered_by.is_some() {
            len += 1;
        }
        if !self.selected_items.is_empty() {
            len += 1;
        }
        if self.inventory_applied {
            len += 1;
        }
        if self.group_name.is_some() {
            len += 1;
        }
        if self.event_name.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.TradeMatch", len)?;
        if self.id != 0 {
            struct_ser.serialize_field("id", &self.id)?;
        }
        if self.user1_id != 0 {
            struct_ser.serialize_field("user1Id", &self.user1_id)?;
        }
        if self.user2_id != 0 {
            struct_ser.serialize_field("user2Id", &self.user2_id)?;
        }
        if !self.status.is_empty() {
            struct_ser.serialize_field("status", &self.status)?;
        }
        if let Some(v) = self.created_at.as_ref() {
            struct_ser.serialize_field("createdAt", v)?;
        }
        if let Some(v) = self.other_user.as_ref() {
            struct_ser.serialize_field("otherUser", v)?;
        }
        if !self.user_haves.is_empty() {
            struct_ser.serialize_field("userHaves", &self.user_haves)?;
        }
        if !self.user_wants.is_empty() {
            struct_ser.serialize_field("userWants", &self.user_wants)?;
        }
        if let Some(v) = self.offered_by.as_ref() {
            struct_ser.serialize_field("offeredBy", v)?;
        }
        if !self.selected_items.is_empty() {
            struct_ser.serialize_field("selectedItems", &self.selected_items)?;
        }
        if self.inventory_applied {
            struct_ser.serialize_field("inventoryApplied", &self.inventory_applied)?;
        }
        if let Some(v) = self.group_name.as_ref() {
            struct_ser.serialize_field("groupName", v)?;
        }
        if let Some(v) = self.event_name.as_ref() {
            struct_ser.serialize_field("eventName", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for TradeMatch {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "id",
            "user1_id",
            "user1Id",
            "user2_id",
            "user2Id",
            "status",
            "created_at",
            "createdAt",
            "other_user",
            "otherUser",
            "user_haves",
            "userHaves",
            "user_wants",
            "userWants",
            "offered_by",
            "offeredBy",
            "selected_items",
            "selectedItems",
            "inventory_applied",
            "inventoryApplied",
            "group_name",
            "groupName",
            "event_name",
            "eventName",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Id,
            User1Id,
            User2Id,
            Status,
            CreatedAt,
            OtherUser,
            UserHaves,
            UserWants,
            OfferedBy,
            SelectedItems,
            InventoryApplied,
            GroupName,
            EventName,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "id" => Ok(GeneratedField::Id),
                            "user1Id" | "user1_id" => Ok(GeneratedField::User1Id),
                            "user2Id" | "user2_id" => Ok(GeneratedField::User2Id),
                            "status" => Ok(GeneratedField::Status),
                            "createdAt" | "created_at" => Ok(GeneratedField::CreatedAt),
                            "otherUser" | "other_user" => Ok(GeneratedField::OtherUser),
                            "userHaves" | "user_haves" => Ok(GeneratedField::UserHaves),
                            "userWants" | "user_wants" => Ok(GeneratedField::UserWants),
                            "offeredBy" | "offered_by" => Ok(GeneratedField::OfferedBy),
                            "selectedItems" | "selected_items" => Ok(GeneratedField::SelectedItems),
                            "inventoryApplied" | "inventory_applied" => Ok(GeneratedField::InventoryApplied),
                            "groupName" | "group_name" => Ok(GeneratedField::GroupName),
                            "eventName" | "event_name" => Ok(GeneratedField::EventName),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = TradeMatch;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.TradeMatch")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<TradeMatch, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut id__ = None;
                let mut user1_id__ = None;
                let mut user2_id__ = None;
                let mut status__ = None;
                let mut created_at__ = None;
                let mut other_user__ = None;
                let mut user_haves__ = None;
                let mut user_wants__ = None;
                let mut offered_by__ = None;
                let mut selected_items__ = None;
                let mut inventory_applied__ = None;
                let mut group_name__ = None;
                let mut event_name__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Id => {
                            if id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("id"));
                            }
                            id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::User1Id => {
                            if user1_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("user1Id"));
                            }
                            user1_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::User2Id => {
                            if user2_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("user2Id"));
                            }
                            user2_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Status => {
                            if status__.is_some() {
                                return Err(serde::de::Error::duplicate_field("status"));
                            }
                            status__ = Some(map_.next_value()?);
                        }
                        GeneratedField::CreatedAt => {
                            if created_at__.is_some() {
                                return Err(serde::de::Error::duplicate_field("createdAt"));
                            }
                            created_at__ = map_.next_value()?;
                        }
                        GeneratedField::OtherUser => {
                            if other_user__.is_some() {
                                return Err(serde::de::Error::duplicate_field("otherUser"));
                            }
                            other_user__ = map_.next_value()?;
                        }
                        GeneratedField::UserHaves => {
                            if user_haves__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userHaves"));
                            }
                            user_haves__ = Some(map_.next_value()?);
                        }
                        GeneratedField::UserWants => {
                            if user_wants__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userWants"));
                            }
                            user_wants__ = Some(map_.next_value()?);
                        }
                        GeneratedField::OfferedBy => {
                            if offered_by__.is_some() {
                                return Err(serde::de::Error::duplicate_field("offeredBy"));
                            }
                            offered_by__ = 
                                map_.next_value::<::std::option::Option<::pbjson::private::NumberDeserialize<_>>>()?.map(|x| x.0)
                            ;
                        }
                        GeneratedField::SelectedItems => {
                            if selected_items__.is_some() {
                                return Err(serde::de::Error::duplicate_field("selectedItems"));
                            }
                            selected_items__ = Some(map_.next_value()?);
                        }
                        GeneratedField::InventoryApplied => {
                            if inventory_applied__.is_some() {
                                return Err(serde::de::Error::duplicate_field("inventoryApplied"));
                            }
                            inventory_applied__ = Some(map_.next_value()?);
                        }
                        GeneratedField::GroupName => {
                            if group_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("groupName"));
                            }
                            group_name__ = map_.next_value()?;
                        }
                        GeneratedField::EventName => {
                            if event_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("eventName"));
                            }
                            event_name__ = map_.next_value()?;
                        }
                    }
                }
                Ok(TradeMatch {
                    id: id__.unwrap_or_default(),
                    user1_id: user1_id__.unwrap_or_default(),
                    user2_id: user2_id__.unwrap_or_default(),
                    status: status__.unwrap_or_default(),
                    created_at: created_at__,
                    other_user: other_user__,
                    user_haves: user_haves__.unwrap_or_default(),
                    user_wants: user_wants__.unwrap_or_default(),
                    offered_by: offered_by__,
                    selected_items: selected_items__.unwrap_or_default(),
                    inventory_applied: inventory_applied__.unwrap_or_default(),
                    group_name: group_name__,
                    event_name: event_name__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.TradeMatch", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for UpdateEventRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.user_id != 0 {
            len += 1;
        }
        if self.name.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.UpdateEventRequest", len)?;
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        if let Some(v) = self.name.as_ref() {
            struct_ser.serialize_field("name", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for UpdateEventRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "user_id",
            "userId",
            "name",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            UserId,
            Name,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            "name" => Ok(GeneratedField::Name),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = UpdateEventRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.UpdateEventRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<UpdateEventRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut user_id__ = None;
                let mut name__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Name => {
                            if name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("name"));
                            }
                            name__ = map_.next_value()?;
                        }
                    }
                }
                Ok(UpdateEventRequest {
                    user_id: user_id__.unwrap_or_default(),
                    name: name__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.UpdateEventRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for UpdateGroupRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.event_id != 0 {
            len += 1;
        }
        if self.user_id != 0 {
            len += 1;
        }
        if !self.group_name.is_empty() {
            len += 1;
        }
        if self.description.is_some() {
            len += 1;
        }
        if self.photo_url.is_some() {
            len += 1;
        }
        if self.display_name.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.UpdateGroupRequest", len)?;
        if self.event_id != 0 {
            struct_ser.serialize_field("eventId", &self.event_id)?;
        }
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        if !self.group_name.is_empty() {
            struct_ser.serialize_field("groupName", &self.group_name)?;
        }
        if let Some(v) = self.description.as_ref() {
            struct_ser.serialize_field("description", v)?;
        }
        if let Some(v) = self.photo_url.as_ref() {
            struct_ser.serialize_field("photoUrl", v)?;
        }
        if let Some(v) = self.display_name.as_ref() {
            struct_ser.serialize_field("displayName", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for UpdateGroupRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "event_id",
            "eventId",
            "user_id",
            "userId",
            "group_name",
            "groupName",
            "description",
            "photo_url",
            "photoUrl",
            "display_name",
            "displayName",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            EventId,
            UserId,
            GroupName,
            Description,
            PhotoUrl,
            DisplayName,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "eventId" | "event_id" => Ok(GeneratedField::EventId),
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            "groupName" | "group_name" => Ok(GeneratedField::GroupName),
                            "description" => Ok(GeneratedField::Description),
                            "photoUrl" | "photo_url" => Ok(GeneratedField::PhotoUrl),
                            "displayName" | "display_name" => Ok(GeneratedField::DisplayName),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = UpdateGroupRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.UpdateGroupRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<UpdateGroupRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut event_id__ = None;
                let mut user_id__ = None;
                let mut group_name__ = None;
                let mut description__ = None;
                let mut photo_url__ = None;
                let mut display_name__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::EventId => {
                            if event_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("eventId"));
                            }
                            event_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::GroupName => {
                            if group_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("groupName"));
                            }
                            group_name__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Description => {
                            if description__.is_some() {
                                return Err(serde::de::Error::duplicate_field("description"));
                            }
                            description__ = map_.next_value()?;
                        }
                        GeneratedField::PhotoUrl => {
                            if photo_url__.is_some() {
                                return Err(serde::de::Error::duplicate_field("photoUrl"));
                            }
                            photo_url__ = map_.next_value()?;
                        }
                        GeneratedField::DisplayName => {
                            if display_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("displayName"));
                            }
                            display_name__ = map_.next_value()?;
                        }
                    }
                }
                Ok(UpdateGroupRequest {
                    event_id: event_id__.unwrap_or_default(),
                    user_id: user_id__.unwrap_or_default(),
                    group_name: group_name__.unwrap_or_default(),
                    description: description__,
                    photo_url: photo_url__,
                    display_name: display_name__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.UpdateGroupRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for UpdateInventoryRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.user_id != 0 {
            len += 1;
        }
        if self.merch_id != 0 {
            len += 1;
        }
        if !self.status.is_empty() {
            len += 1;
        }
        if self.quantity != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.UpdateInventoryRequest", len)?;
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        if self.merch_id != 0 {
            struct_ser.serialize_field("merchId", &self.merch_id)?;
        }
        if !self.status.is_empty() {
            struct_ser.serialize_field("status", &self.status)?;
        }
        if self.quantity != 0 {
            struct_ser.serialize_field("quantity", &self.quantity)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for UpdateInventoryRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "user_id",
            "userId",
            "merch_id",
            "merchId",
            "status",
            "quantity",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            UserId,
            MerchId,
            Status,
            Quantity,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            "merchId" | "merch_id" => Ok(GeneratedField::MerchId),
                            "status" => Ok(GeneratedField::Status),
                            "quantity" => Ok(GeneratedField::Quantity),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = UpdateInventoryRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.UpdateInventoryRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<UpdateInventoryRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut user_id__ = None;
                let mut merch_id__ = None;
                let mut status__ = None;
                let mut quantity__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::MerchId => {
                            if merch_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("merchId"));
                            }
                            merch_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Status => {
                            if status__.is_some() {
                                return Err(serde::de::Error::duplicate_field("status"));
                            }
                            status__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Quantity => {
                            if quantity__.is_some() {
                                return Err(serde::de::Error::duplicate_field("quantity"));
                            }
                            quantity__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(UpdateInventoryRequest {
                    user_id: user_id__.unwrap_or_default(),
                    merch_id: merch_id__.unwrap_or_default(),
                    status: status__.unwrap_or_default(),
                    quantity: quantity__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.UpdateInventoryRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for UpdateMatchStatusRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.status.is_empty() {
            len += 1;
        }
        if self.user_id != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.UpdateMatchStatusRequest", len)?;
        if !self.status.is_empty() {
            struct_ser.serialize_field("status", &self.status)?;
        }
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for UpdateMatchStatusRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "status",
            "user_id",
            "userId",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Status,
            UserId,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "status" => Ok(GeneratedField::Status),
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = UpdateMatchStatusRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.UpdateMatchStatusRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<UpdateMatchStatusRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut status__ = None;
                let mut user_id__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Status => {
                            if status__.is_some() {
                                return Err(serde::de::Error::duplicate_field("status"));
                            }
                            status__ = Some(map_.next_value()?);
                        }
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(UpdateMatchStatusRequest {
                    status: status__.unwrap_or_default(),
                    user_id: user_id__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.UpdateMatchStatusRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for UpdateMerchRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.user_id != 0 {
            len += 1;
        }
        if self.name.is_some() {
            len += 1;
        }
        if self.photo_url.is_some() {
            len += 1;
        }
        if self.group_name.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.UpdateMerchRequest", len)?;
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        if let Some(v) = self.name.as_ref() {
            struct_ser.serialize_field("name", v)?;
        }
        if let Some(v) = self.photo_url.as_ref() {
            struct_ser.serialize_field("photoUrl", v)?;
        }
        if let Some(v) = self.group_name.as_ref() {
            struct_ser.serialize_field("groupName", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for UpdateMerchRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "user_id",
            "userId",
            "name",
            "photo_url",
            "photoUrl",
            "group_name",
            "groupName",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            UserId,
            Name,
            PhotoUrl,
            GroupName,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            "name" => Ok(GeneratedField::Name),
                            "photoUrl" | "photo_url" => Ok(GeneratedField::PhotoUrl),
                            "groupName" | "group_name" => Ok(GeneratedField::GroupName),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = UpdateMerchRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.UpdateMerchRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<UpdateMerchRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut user_id__ = None;
                let mut name__ = None;
                let mut photo_url__ = None;
                let mut group_name__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Name => {
                            if name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("name"));
                            }
                            name__ = map_.next_value()?;
                        }
                        GeneratedField::PhotoUrl => {
                            if photo_url__.is_some() {
                                return Err(serde::de::Error::duplicate_field("photoUrl"));
                            }
                            photo_url__ = map_.next_value()?;
                        }
                        GeneratedField::GroupName => {
                            if group_name__.is_some() {
                                return Err(serde::de::Error::duplicate_field("groupName"));
                            }
                            group_name__ = map_.next_value()?;
                        }
                    }
                }
                Ok(UpdateMerchRequest {
                    user_id: user_id__.unwrap_or_default(),
                    name: name__,
                    photo_url: photo_url__,
                    group_name: group_name__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.UpdateMerchRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for UpdateUserRoleRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if !self.role.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.UpdateUserRoleRequest", len)?;
        if !self.role.is_empty() {
            struct_ser.serialize_field("role", &self.role)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for UpdateUserRoleRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "role",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Role,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "role" => Ok(GeneratedField::Role),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = UpdateUserRoleRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.UpdateUserRoleRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<UpdateUserRoleRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut role__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Role => {
                            if role__.is_some() {
                                return Err(serde::de::Error::duplicate_field("role"));
                            }
                            role__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(UpdateUserRoleRequest {
                    role: role__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.UpdateUserRoleRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for UpdateUsernameRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.user_id != 0 {
            len += 1;
        }
        if !self.username.is_empty() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.UpdateUsernameRequest", len)?;
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        if !self.username.is_empty() {
            struct_ser.serialize_field("username", &self.username)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for UpdateUsernameRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "user_id",
            "userId",
            "username",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            UserId,
            Username,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            "username" => Ok(GeneratedField::Username),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = UpdateUsernameRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.UpdateUsernameRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<UpdateUsernameRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut user_id__ = None;
                let mut username__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Username => {
                            if username__.is_some() {
                                return Err(serde::de::Error::duplicate_field("username"));
                            }
                            username__ = Some(map_.next_value()?);
                        }
                    }
                }
                Ok(UpdateUsernameRequest {
                    user_id: user_id__.unwrap_or_default(),
                    username: username__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.UpdateUsernameRequest", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for User {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.id != 0 {
            len += 1;
        }
        if !self.username.is_empty() {
            len += 1;
        }
        if self.uuid.is_some() {
            len += 1;
        }
        if self.device_token.is_some() {
            len += 1;
        }
        if self.created_at.is_some() {
            len += 1;
        }
        if self.role.is_some() {
            len += 1;
        }
        if self.is_banned.is_some() {
            len += 1;
        }
        if self.ban_reason.is_some() {
            len += 1;
        }
        if self.banned_until.is_some() {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.User", len)?;
        if self.id != 0 {
            struct_ser.serialize_field("id", &self.id)?;
        }
        if !self.username.is_empty() {
            struct_ser.serialize_field("username", &self.username)?;
        }
        if let Some(v) = self.uuid.as_ref() {
            struct_ser.serialize_field("uuid", v)?;
        }
        if let Some(v) = self.device_token.as_ref() {
            struct_ser.serialize_field("deviceToken", v)?;
        }
        if let Some(v) = self.created_at.as_ref() {
            struct_ser.serialize_field("createdAt", v)?;
        }
        if let Some(v) = self.role.as_ref() {
            struct_ser.serialize_field("role", v)?;
        }
        if let Some(v) = self.is_banned.as_ref() {
            struct_ser.serialize_field("isBanned", v)?;
        }
        if let Some(v) = self.ban_reason.as_ref() {
            struct_ser.serialize_field("banReason", v)?;
        }
        if let Some(v) = self.banned_until.as_ref() {
            struct_ser.serialize_field("bannedUntil", v)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for User {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "id",
            "username",
            "uuid",
            "device_token",
            "deviceToken",
            "created_at",
            "createdAt",
            "role",
            "is_banned",
            "isBanned",
            "ban_reason",
            "banReason",
            "banned_until",
            "bannedUntil",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            Id,
            Username,
            Uuid,
            DeviceToken,
            CreatedAt,
            Role,
            IsBanned,
            BanReason,
            BannedUntil,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "id" => Ok(GeneratedField::Id),
                            "username" => Ok(GeneratedField::Username),
                            "uuid" => Ok(GeneratedField::Uuid),
                            "deviceToken" | "device_token" => Ok(GeneratedField::DeviceToken),
                            "createdAt" | "created_at" => Ok(GeneratedField::CreatedAt),
                            "role" => Ok(GeneratedField::Role),
                            "isBanned" | "is_banned" => Ok(GeneratedField::IsBanned),
                            "banReason" | "ban_reason" => Ok(GeneratedField::BanReason),
                            "bannedUntil" | "banned_until" => Ok(GeneratedField::BannedUntil),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = User;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.User")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<User, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut id__ = None;
                let mut username__ = None;
                let mut uuid__ = None;
                let mut device_token__ = None;
                let mut created_at__ = None;
                let mut role__ = None;
                let mut is_banned__ = None;
                let mut ban_reason__ = None;
                let mut banned_until__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::Id => {
                            if id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("id"));
                            }
                            id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                        GeneratedField::Username => {
                            if username__.is_some() {
                                return Err(serde::de::Error::duplicate_field("username"));
                            }
                            username__ = Some(map_.next_value()?);
                        }
                        GeneratedField::Uuid => {
                            if uuid__.is_some() {
                                return Err(serde::de::Error::duplicate_field("uuid"));
                            }
                            uuid__ = map_.next_value()?;
                        }
                        GeneratedField::DeviceToken => {
                            if device_token__.is_some() {
                                return Err(serde::de::Error::duplicate_field("deviceToken"));
                            }
                            device_token__ = map_.next_value()?;
                        }
                        GeneratedField::CreatedAt => {
                            if created_at__.is_some() {
                                return Err(serde::de::Error::duplicate_field("createdAt"));
                            }
                            created_at__ = map_.next_value()?;
                        }
                        GeneratedField::Role => {
                            if role__.is_some() {
                                return Err(serde::de::Error::duplicate_field("role"));
                            }
                            role__ = map_.next_value()?;
                        }
                        GeneratedField::IsBanned => {
                            if is_banned__.is_some() {
                                return Err(serde::de::Error::duplicate_field("isBanned"));
                            }
                            is_banned__ = map_.next_value()?;
                        }
                        GeneratedField::BanReason => {
                            if ban_reason__.is_some() {
                                return Err(serde::de::Error::duplicate_field("banReason"));
                            }
                            ban_reason__ = map_.next_value()?;
                        }
                        GeneratedField::BannedUntil => {
                            if banned_until__.is_some() {
                                return Err(serde::de::Error::duplicate_field("bannedUntil"));
                            }
                            banned_until__ = map_.next_value()?;
                        }
                    }
                }
                Ok(User {
                    id: id__.unwrap_or_default(),
                    username: username__.unwrap_or_default(),
                    uuid: uuid__,
                    device_token: device_token__,
                    created_at: created_at__,
                    role: role__,
                    is_banned: is_banned__,
                    ban_reason: ban_reason__,
                    banned_until: banned_until__,
                })
            }
        }
        deserializer.deserialize_struct("ymatch.User", FIELDS, GeneratedVisitor)
    }
}
impl serde::Serialize for UserActionRequest {
    #[allow(deprecated)]
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        use serde::ser::SerializeStruct;
        let mut len = 0;
        if self.user_id != 0 {
            len += 1;
        }
        let mut struct_ser = serializer.serialize_struct("ymatch.UserActionRequest", len)?;
        if self.user_id != 0 {
            struct_ser.serialize_field("userId", &self.user_id)?;
        }
        struct_ser.end()
    }
}
impl<'de> serde::Deserialize<'de> for UserActionRequest {
    #[allow(deprecated)]
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        const FIELDS: &[&str] = &[
            "user_id",
            "userId",
        ];

        #[allow(clippy::enum_variant_names)]
        enum GeneratedField {
            UserId,
        }
        impl<'de> serde::Deserialize<'de> for GeneratedField {
            fn deserialize<D>(deserializer: D) -> std::result::Result<GeneratedField, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                struct GeneratedVisitor;

                impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
                    type Value = GeneratedField;

                    fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                        write!(formatter, "expected one of: {:?}", &FIELDS)
                    }

                    #[allow(unused_variables)]
                    fn visit_str<E>(self, value: &str) -> std::result::Result<GeneratedField, E>
                    where
                        E: serde::de::Error,
                    {
                        match value {
                            "userId" | "user_id" => Ok(GeneratedField::UserId),
                            _ => Err(serde::de::Error::unknown_field(value, FIELDS)),
                        }
                    }
                }
                deserializer.deserialize_identifier(GeneratedVisitor)
            }
        }
        struct GeneratedVisitor;
        impl<'de> serde::de::Visitor<'de> for GeneratedVisitor {
            type Value = UserActionRequest;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("struct ymatch.UserActionRequest")
            }

            fn visit_map<V>(self, mut map_: V) -> std::result::Result<UserActionRequest, V::Error>
                where
                    V: serde::de::MapAccess<'de>,
            {
                let mut user_id__ = None;
                while let Some(k) = map_.next_key()? {
                    match k {
                        GeneratedField::UserId => {
                            if user_id__.is_some() {
                                return Err(serde::de::Error::duplicate_field("userId"));
                            }
                            user_id__ = 
                                Some(map_.next_value::<::pbjson::private::NumberDeserialize<_>>()?.0)
                            ;
                        }
                    }
                }
                Ok(UserActionRequest {
                    user_id: user_id__.unwrap_or_default(),
                })
            }
        }
        deserializer.deserialize_struct("ymatch.UserActionRequest", FIELDS, GeneratedVisitor)
    }
}
